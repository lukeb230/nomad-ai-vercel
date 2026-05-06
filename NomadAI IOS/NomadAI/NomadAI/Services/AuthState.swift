//
//  AuthState.swift
//  Process-wide @Observable singleton tracking the user's auth status.
//
//  Subscribes to SupabaseService.shared.client.auth.authStateChanges on init.
//  The SDK fires the resumed session immediately on subscribe (via Keychain
//  storage), and again on every sign-in / sign-out / refresh — so the
//  Settings UI flips automatically without manual session polling.
//
//  Phase 7b addition: on the first signed-in event for a given user, we
//  auto-create a local Profile row (if none exists) seeded with their email.
//  The next push sends it to Supabase; future devices pull it.
//

import Foundation
import SwiftData
import Supabase

@Observable
final class AuthState {
    static let shared = AuthState()

    private(set) var session: Session?

    var isSignedIn: Bool { session != nil }
    var userId: String? { session?.user.id.uuidString }
    var email: String? { session?.user.email }

    @ObservationIgnored private var listenerTask: Task<Void, Never>?

    /// Set by NomadAIApp once the ModelContainer is up so we can seed a Profile row.
    @ObservationIgnored var modelContext: ModelContext?

    private init() {
        listenerTask = Task { [weak self] in
            for await (event, session) in await SupabaseService.shared.client.auth.authStateChanges {
                await MainActor.run {
                    self?.session = session
                    if (event == .signedIn || event == .initialSession), session != nil {
                        self?.ensureLocalProfile()
                    }
                }
            }
        }
    }

    func signOut() async {
        await NotificationService.shared.wipeAll()
        try? await SupabaseService.shared.client.auth.signOut()
    }

    /// Make sure a local Profile row exists for the signed-in user. Idempotent.
    private func ensureLocalProfile() {
        guard let ctx = modelContext, let uid = userId else { return }
        var fetch = FetchDescriptor<Profile>(predicate: #Predicate { $0.userId == uid })
        fetch.fetchLimit = 1
        if (try? ctx.fetch(fetch).first) != nil { return }
        let profile = Profile(
            userId: uid,
            email: email,
            updatedAt: Date()
        )
        ctx.insert(profile)
        try? ctx.save()
    }
}
