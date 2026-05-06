//
//  RouteBuilderState.swift
//  Process-wide state for the route-building flow.
//
//  When the user asks for a route, NomadAI doesn't auto-build one. Instead:
//    1. The flow activates with the user's route description.
//    2. Claude returns candidate stops as cards.
//    3. The user taps "Add to route" on cards they want.
//    4. The user taps "Build route" in the inline panel — creates a Trip
//       in SwiftData and navigates to the Saved tab's Route mode.
//

import Foundation
import SwiftData
import OSLog

private let routeLog = Logger(subsystem: "LukeBrowne.NomadAI", category: "route-builder")

@Observable
@MainActor
final class RouteBuilderState {
    static let shared = RouteBuilderState()

    /// Non-empty while a route is being assembled. Drives panel visibility +
    /// CampsiteCard's button morph from "Trip" → "Add to route".
    var routeDescription: String = ""

    /// Stable Campsite ids the user has tapped "Add to route" for, in the
    /// order they were tapped (becomes TripStop.order on build).
    var selectedStopIds: [String] = []

    var isActive: Bool { !routeDescription.isEmpty }
    var stopCount: Int { selectedStopIds.count }

    private init() {}

    // MARK: - Lifecycle

    /// Activates the flow with the user's route description. If a flow is
    /// already active, the description updates but selections are preserved
    /// (lets the user refine the route via additional queries).
    func start(description: String) {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        routeDescription = trimmed
        routeLog.notice("route builder started: \(trimmed, privacy: .public)")
    }

    /// User cancelled or finished. Clears all state.
    func cancel() {
        routeDescription = ""
        selectedStopIds.removeAll()
    }

    // MARK: - Selection

    func contains(_ campsiteId: String) -> Bool {
        selectedStopIds.contains(campsiteId)
    }

    /// Adds or removes a campsite id from the selection. Returns the new state
    /// so callers can update their UI without re-reading.
    @discardableResult
    func toggle(_ campsiteId: String) -> Bool {
        if let idx = selectedStopIds.firstIndex(of: campsiteId) {
            selectedStopIds.remove(at: idx)
            return false
        }
        selectedStopIds.append(campsiteId)
        return true
    }

    // MARK: - Build

    /// Creates a new active Trip from the selected stops, in selection order.
    /// Coexists with any existing active trips — Saved tab's Route mode picker
    /// surfaces all of them.
    /// Returns the new Trip on success.
    @discardableResult
    func build(in ctx: ModelContext) -> Trip? {
        guard !selectedStopIds.isEmpty else {
            routeLog.warning("build called with no stops selected; ignoring")
            return nil
        }

        // Look up Campsites in the order they were selected.
        var orderedSites: [(String, Campsite)] = []
        for id in selectedStopIds {
            let descriptor = FetchDescriptor<Campsite>(predicate: #Predicate { $0.id == id })
            if let site = try? ctx.fetch(descriptor).first {
                orderedSites.append((id, site))
            } else {
                routeLog.warning("could not find Campsite with id \(id, privacy: .public); skipping")
            }
        }
        guard !orderedSites.isEmpty else {
            routeLog.error("no resolvable campsites for build")
            return nil
        }

        let trip = Trip(id: UUID(), startedAt: Date())
        trip.updatedAt = Date()
        ctx.insert(trip)

        for (i, pair) in orderedSites.enumerated() {
            let stop = TripStop(
                order: i,
                campsiteId: pair.0,
                campsiteName: pair.1.name,
                lat: pair.1.lat,
                lng: pair.1.lng
            )
            stop.trip = trip
            ctx.insert(stop)
        }

        do {
            try ctx.save()
        } catch {
            routeLog.error("save failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        routeLog.notice("built trip with \(orderedSites.count) stops")
        cancel()
        return trip
    }
}
