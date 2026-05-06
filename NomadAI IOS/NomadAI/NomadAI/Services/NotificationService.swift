//
//  NotificationService.swift
//  Local trip-stop reminders via UNUserNotificationCenter.
//
//  One @Observable singleton. Reads/writes pending requests with the prefix
//  "stop-" so we can wipe + rebuild safely without touching anyone else's
//  notifications. No APNs / push — pure local UNCalendarNotificationTrigger.
//
//  Lifecycle hooks:
//    - NomadAIApp.task             → refreshStatus + initial rebuildSchedule
//    - .scenePhase = .active       → rebuildSchedule (cross-device pull may have changed dates)
//    - SyncService.fullSync done   → rebuildSchedule
//    - SavedView StopDateSheet save → rebuildSchedule for that trip
//    - MapView markVisited          → rebuildSchedule (filters out done stops)
//    - AuthState.signOut           → wipeAll
//

import Foundation
import OSLog
import SwiftData
import UserNotifications

private let notifLog = Logger(subsystem: "LukeBrowne.NomadAI", category: "notif")

@Observable
final class NotificationService {
    static let shared = NotificationService()

    private(set) var status: UNAuthorizationStatus = .notDetermined
    private(set) var scheduledCount: Int = 0

    private init() {
        Task { await refreshStatus() }
    }

    // MARK: - Permission

    @discardableResult
    func requestPermission() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshStatus()
        notifLog.notice("requestPermission granted=\(granted)")
        return granted
    }

    func refreshStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run { self.status = settings.authorizationStatus }
    }

    // MARK: - Schedule

    /// Wipe all NomadAI-owned reminders, then re-schedule from the given trips' upcoming stops.
    /// Idempotent — safe to call any time after a mutation.
    func rebuildSchedule(from trips: [Trip]) async {
        // Make sure we have an up-to-date status.
        await refreshStatus()
        guard status == .authorized || status == .provisional else {
            await wipeAll()
            return
        }
        let center = UNUserNotificationCenter.current()
        await wipeAll()

        var count = 0
        for trip in trips where trip.completedAt == nil {
            for stop in trip.sortedStops {
                guard stop.order >= trip.currentStopIndex,        // skip already-visited
                      let date = stop.scheduledDate,
                      date > Date() else { continue }
                let req = makeRequest(for: stop, fireAt: date)
                do {
                    try await center.add(req)
                    count += 1
                } catch {
                    notifLog.error("failed to schedule \(req.identifier): \(error.localizedDescription)")
                }
            }
        }
        await MainActor.run { self.scheduledCount = count }
        notifLog.notice("rebuildSchedule scheduled=\(count)")
    }

    /// Cancel every NomadAI-owned reminder. Used on sign-out.
    func wipeAll() async {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let ours = pending.filter { $0.identifier.hasPrefix("stop-") }.map(\.identifier)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ours)
        await MainActor.run { self.scheduledCount = 0 }
    }

    // MARK: - Internal

    private func makeRequest(for stop: TripStop, fireAt date: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "NomadAI · Coming up"
        content.body = stop.campsiteName
        content.sound = .default

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

        let id = "stop-\(stop.persistentModelID.hashValue)"
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }
}
