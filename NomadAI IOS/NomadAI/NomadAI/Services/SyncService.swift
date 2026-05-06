//
//  SyncService.swift
//  Pull/push sync between SwiftData and Supabase, with last-write-wins by
//  `updatedAt` timestamps. One singleton, four tables.
//
//  Threading model:
//    - The class itself is NOT @MainActor. The auth listener loop runs on a
//      detached background task so it doesn't tie up the main thread.
//    - SwiftData operations (fetch / save) hop to @MainActor explicitly.
//    - Network calls (PostgREST upserts/selects) run off main via the SDK.
//
//  Lifecycle:
//    - NomadAIApp.task → SyncService.shared.start(context:) — wires the
//      ModelContext.didSave observer + auth-state listener.
//    - Auth flips to .signedIn / .initialSession → fullSync() (pull, then push).
//    - .scenePhase becomes .active → fullSync().
//    - Local mutation → ModelContext.didSave → schedulePush() (1.5s debounce).
//

import Foundation
import OSLog
import SwiftData
import Supabase

private let syncLog = Logger(subsystem: "LukeBrowne.NomadAI", category: "sync")

@Observable
final class SyncService {
    static let shared = SyncService()

    @ObservationIgnored private var modelContext: ModelContext?
    @ObservationIgnored private var pushTask: Task<Void, Never>?
    @ObservationIgnored private var saveObserver: NSObjectProtocol?
    @ObservationIgnored private var authListenerTask: Task<Void, Never>?
    @ObservationIgnored private var isApplyingRemote: Bool = false
    @ObservationIgnored private var isSyncing: Bool = false
    /// Set true if any local save fires while `isApplyingRemote` is suppressing
    /// the schedulePush observer. After sync completes we run one follow-up push
    /// so the user mutation isn't stranded until next foreground.
    @ObservationIgnored private var savedDuringSync: Bool = false

    private(set) var lastSyncError: String?
    private(set) var lastSyncedAt: Date?

    private init() {}

    deinit {
        if let saveObserver { NotificationCenter.default.removeObserver(saveObserver) }
        authListenerTask?.cancel()
        pushTask?.cancel()
    }

    @MainActor
    func start(context: ModelContext) {
        guard self.modelContext == nil else { return }     // idempotent
        self.modelContext = context
        syncLog.notice("start() — service wired up")

        saveObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if self.isApplyingRemote {
                // A user mutation happened mid-sync. Note it so we schedule a
                // follow-up push once sync completes.
                self.savedDuringSync = true
                return
            }
            self.schedulePush()
        }

        // Detached so the listener loop does not run on main.
        authListenerTask = Task.detached { [weak self] in
            for await (event, session) in await SupabaseService.shared.client.auth.authStateChanges {
                guard let self else { return }
                syncLog.notice("auth event=\(String(describing: event)) signedIn=\(session != nil)")
                if (event == .signedIn || event == .initialSession), session != nil {
                    try? await Task.sleep(for: .milliseconds(800))
                    await self.fullSync()
                }
            }
        }
    }

    func onForeground() async {
        let signedIn = await MainActor.run { AuthState.shared.isSignedIn }
        guard signedIn else { return }
        await fullSync()
    }

    private func fullSync() async {
        let canStart = await MainActor.run { () -> Bool in
            guard !self.isSyncing, self.modelContext != nil, AuthState.shared.isSignedIn else {
                syncLog.notice("fullSync skipped — isSyncing=\(self.isSyncing) hasCtx=\(self.modelContext != nil) signedIn=\(AuthState.shared.isSignedIn)")
                return false
            }
            self.isSyncing = true
            self.lastSyncError = nil
            return true
        }
        guard canStart else { return }
        syncLog.notice("fullSync start")
        defer {
            Task { @MainActor in
                self.isSyncing = false
                self.lastSyncedAt = Date()
                syncLog.notice("fullSync done; lastError=\(self.lastSyncError ?? "nil")")
                // Refresh local notification schedule from the (possibly updated) trips.
                let trips = (try? self.modelContext?.fetch(FetchDescriptor<Trip>())) ?? []
                Task { await NotificationService.shared.rebuildSchedule(from: trips) }
            }
        }
        await pull()
        await push()
    }

    @MainActor
    private func schedulePush() {
        guard AuthState.shared.isSignedIn else {
            syncLog.notice("schedulePush skipped — not signed in")
            return
        }
        syncLog.notice("schedulePush — debounced 1.5s")
        pushTask?.cancel()
        pushTask = Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            if Task.isCancelled { return }
            await self?.push()
        }
    }

    // MARK: - Pull

    private func pull() async {
        guard let userId = await MainActor.run(body: { AuthState.shared.userId }) else { return }
        let client = await SupabaseService.shared.client

        // Network fetches off main.
        var profileRows: [ProfileRow] = []
        var campsiteRows: [CampsiteRow] = []
        var tripRows: [TripRow] = []
        var completedRows: [CompletedTripRow] = []
        do {
            profileRows = try await client.from("user_profiles")
                .select().eq("user_id", value: userId).execute().value
            campsiteRows = try await client.from("user_campsites")
                .select().eq("user_id", value: userId).execute().value
            tripRows = try await client.from("user_trips")
                .select().eq("user_id", value: userId).execute().value
            completedRows = try await client.from("user_completed_trips")
                .select().eq("user_id", value: userId).execute().value
            syncLog.notice("pull fetched profiles=\(profileRows.count) campsites=\(campsiteRows.count) trips=\(tripRows.count) completed=\(completedRows.count)")
        } catch {
            syncLog.error("pull error: \(error.localizedDescription)")
            await MainActor.run {
                self.lastSyncError = "Pull: \(error.localizedDescription)"
            }
            return
        }

        // Apply on main with the isApplyingRemote flag set so our save doesn't echo to push.
        await MainActor.run {
            guard let ctx = self.modelContext else { return }
            self.isApplyingRemote = true
            defer { self.isApplyingRemote = false }
            for row in profileRows { self.mergeProfile(row, ctx: ctx) }
            for row in campsiteRows { self.mergeCampsite(row, ctx: ctx) }
            for row in tripRows { self.mergeTrip(row, ctx: ctx) }
            for row in completedRows { self.mergeCompletedTrip(row, ctx: ctx) }
            try? ctx.save()
        }
    }

    @MainActor
    private func mergeProfile(_ row: ProfileRow, ctx: ModelContext) {
        let uid = row.userId
        var fetch = FetchDescriptor<Profile>(predicate: #Predicate { $0.userId == uid })
        fetch.fetchLimit = 1
        if let local = try? ctx.fetch(fetch).first {
            if (local.updatedAt ?? .distantPast) < row.updatedAt {
                row.apply(to: local)
            }
        } else {
            ctx.insert(Profile(
                userId: row.userId,
                name: row.name,
                avatarURL: row.avatarUrl,
                email: row.email,
                updatedAt: row.updatedAt
            ))
        }
    }

    @MainActor
    private func mergeCampsite(_ row: CampsiteRow, ctx: ModelContext) {
        let cid = row.campsiteId
        var fetch = FetchDescriptor<Campsite>(predicate: #Predicate { $0.id == cid })
        fetch.fetchLimit = 1
        if let local = try? ctx.fetch(fetch).first {
            if (local.updatedAt ?? .distantPast) < row.updatedAt {
                row.apply(to: local)
            }
        } else {
            ctx.insert(row.toModel())
        }
    }

    @MainActor
    private func mergeTrip(_ row: TripRow, ctx: ModelContext) {
        let tid = row.id
        var fetch = FetchDescriptor<Trip>(predicate: #Predicate { $0.id == tid })
        fetch.fetchLimit = 1
        if let local = try? ctx.fetch(fetch).first {
            if (local.updatedAt ?? .distantPast) < row.updatedAt {
                row.apply(to: local, in: ctx)
            }
        } else {
            ctx.insert(row.toModel(in: ctx))
        }
    }

    @MainActor
    private func mergeCompletedTrip(_ row: CompletedTripRow, ctx: ModelContext) {
        let cid = row.id
        var fetch = FetchDescriptor<CompletedTrip>(predicate: #Predicate { $0.id == cid })
        fetch.fetchLimit = 1
        if let local = try? ctx.fetch(fetch).first {
            if (local.updatedAt ?? .distantPast) < row.updatedAt {
                row.apply(to: local)
            }
        } else {
            ctx.insert(row.toModel())
        }
    }

    // MARK: - Push

    private func push() async {
        guard let userId = await MainActor.run(body: { AuthState.shared.userId }) else { return }
        let client = await SupabaseService.shared.client

        // Suppress observer-triggered re-pushes for the entire push duration.
        // Mutations during this window flip `savedDuringSync`, which triggers a
        // single follow-up push at the end.
        await MainActor.run {
            self.savedDuringSync = false
            self.isApplyingRemote = true
        }
        defer {
            Task { @MainActor in
                self.isApplyingRemote = false
                if self.savedDuringSync {
                    self.savedDuringSync = false
                    self.schedulePush()
                }
            }
        }

        // Build all rows on main; lazy-init updatedAt where missing.
        let snapshot = await MainActor.run { () -> (
            profiles: [ProfileRow],
            campsites: [CampsiteRow],
            trips: [TripRow],
            completed: [CompletedTripRow]
        ) in
            guard let ctx = self.modelContext else { return ([], [], [], []) }
            var profileRows: [ProfileRow] = []
            var campsiteRows: [CampsiteRow] = []
            var tripRows: [TripRow] = []
            var completedRows: [CompletedTripRow] = []
            do {
                let profiles = try ctx.fetch(FetchDescriptor<Profile>(
                    predicate: #Predicate { $0.userId == userId }
                ))
                for p in profiles {
                    if p.updatedAt == nil { p.updatedAt = Date() }
                    profileRows.append(ProfileRow(from: p))
                }
                let campsites = try ctx.fetch(FetchDescriptor<Campsite>(
                    predicate: #Predicate { $0.updatedAt != nil }
                ))
                for c in campsites { campsiteRows.append(CampsiteRow(from: c, userId: userId)) }
                let trips = try ctx.fetch(FetchDescriptor<Trip>())
                for t in trips {
                    if t.updatedAt == nil { t.updatedAt = Date() }
                    tripRows.append(TripRow(from: t, userId: userId))
                }
                let completed = try ctx.fetch(FetchDescriptor<CompletedTrip>())
                for c in completed {
                    if c.updatedAt == nil { c.updatedAt = Date() }
                    completedRows.append(CompletedTripRow(from: c, userId: userId))
                }
            } catch {
                self.lastSyncError = "Push fetch: \(error.localizedDescription)"
            }
            // Persist any lazy-init updatedAt mutations. isApplyingRemote is
            // already set by the outer push() so this save doesn't echo back.
            try? ctx.save()
            return (profileRows, campsiteRows, tripRows, completedRows)
        }

        syncLog.notice("push uploading profiles=\(snapshot.profiles.count) campsites=\(snapshot.campsites.count) trips=\(snapshot.trips.count) completed=\(snapshot.completed.count)")
        // Network upserts off main.
        do {
            if !snapshot.profiles.isEmpty {
                try await client.from("user_profiles")
                    .upsert(snapshot.profiles, onConflict: "user_id").execute()
            }
            if !snapshot.campsites.isEmpty {
                try await client.from("user_campsites")
                    .upsert(snapshot.campsites, onConflict: "user_id,campsite_id").execute()
            }
            if !snapshot.trips.isEmpty {
                try await client.from("user_trips")
                    .upsert(snapshot.trips, onConflict: "id").execute()
            }
            if !snapshot.completed.isEmpty {
                try await client.from("user_completed_trips")
                    .upsert(snapshot.completed, onConflict: "id").execute()
            }
            syncLog.notice("push done")
        } catch {
            syncLog.error("push error: \(error.localizedDescription)")
            await MainActor.run {
                self.lastSyncError = "Push: \(error.localizedDescription)"
            }
        }
    }
}
