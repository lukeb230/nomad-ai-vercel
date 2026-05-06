//
//  NPSAlertsService.swift
//  Fetches active NPS alerts for the user's current state and exposes them as
//  observable state so banner views on Search / Map / Saved can react.
//
//  Reverse-geocodes lat/lng → state code via CLGeocoder, calls the
//  `nps-alerts` Edge Function, caches by state code for 1 hour. Filters out
//  the "Information" category (low signal) — we surface only Danger, Park
//  Closure, and Caution.
//

import Foundation
import CoreLocation
import Supabase
import OSLog

private let alertLog = Logger(subsystem: "LukeBrowne.NomadAI", category: "nps-alerts")

struct NPSAlert: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let description: String
    let category: String
    let parkCode: String
    let parkName: String
    let url: String
    let lastIndexed: String

    /// Categories we surface. NPS also has "Information" which is mostly low
    /// signal (e.g. "park is open").
    static let surfaceCategories: Set<String> = ["Danger", "Park Closure", "Caution"]

    var isMajor: Bool { Self.surfaceCategories.contains(category) }
}

@Observable
@MainActor
final class NPSAlertsService {
    static let shared = NPSAlertsService()

    /// Alerts for the currently-resolved state. Banner views read this.
    var alerts: [NPSAlert] = []
    var stateCode: String? = nil

    @ObservationIgnored
    private var cache: [String: (alerts: [NPSAlert], at: Date)] = [:]

    @ObservationIgnored
    private var inflight: Task<Void, Never>? = nil

    private let ttl: TimeInterval = 3600  // 1 hour

    private init() {}

    /// Refresh alerts for the state covering `(lat, lng)`. Used as the initial
    /// load when a tab appears (device-location-based). Cheap to call
    /// repeatedly — TTL'd cache + in-flight dedupe.
    func refresh(lat: Double, lng: Double) async {
        if let task = inflight {
            await task.value
            return
        }
        let task = Task<Void, Never> { [weak self] in
            await self?.refreshInternal(lat: lat, lng: lng)
        }
        inflight = task
        await task.value
        inflight = nil
    }

    /// Refresh alerts directly for a specific state code. Used after search
    /// results come back so the banner reflects what the user actually
    /// searched for, not their device location.
    func refreshForState(stateCode: String) async {
        let resolved = stateCode.uppercased()
        guard resolved.count == 2 else { return }
        if let cached = cache[resolved], Date().timeIntervalSince(cached.at) < ttl {
            self.stateCode = resolved
            self.alerts = cached.alerts
            return
        }
        do {
            let fetched = try await fetchAlerts(stateCode: resolved)
            let major = fetched.filter(\.isMajor)
            cache[resolved] = (major, Date())
            self.stateCode = resolved
            self.alerts = major
            alertLog.notice("refreshForState \(resolved): \(fetched.count) alerts, \(major.count) major")
        } catch {
            alertLog.error("refreshForState \(resolved) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func refreshInternal(lat: Double, lng: Double) async {
        guard let resolved = await reverseGeocodeState(lat: lat, lng: lng) else {
            alertLog.warning("reverse-geocode failed; skipping refresh")
            return
        }
        if let cached = cache[resolved], Date().timeIntervalSince(cached.at) < ttl {
            stateCode = resolved
            alerts = cached.alerts
            return
        }
        do {
            let fetched = try await fetchAlerts(stateCode: resolved)
            let major = fetched.filter(\.isMajor)
            cache[resolved] = (major, Date())
            stateCode = resolved
            alerts = major
            alertLog.notice("fetched \(fetched.count) alerts for \(resolved); \(major.count) major")
        } catch {
            alertLog.error("fetch failed for \(resolved): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func reverseGeocodeState(lat: Double, lng: Double) async -> String? {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: lat, longitude: lng)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            return placemarks.first?.administrativeArea
        } catch {
            alertLog.error("CLGeocoder error: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private struct EdgeResponse: Decodable {
        let stateCode: String
        let parks: Int
        let alerts: [NPSAlert]
    }

    private func fetchAlerts(stateCode: String) async throws -> [NPSAlert] {
        let payload: [String: AnyJSON] = [
            "stateCode": .string(stateCode),
        ]
        let response: EdgeResponse = try await SupabaseService.shared.client.functions
            .invoke("nps-alerts", options: FunctionInvokeOptions(body: payload))
        return response.alerts
    }
}
