//
//  RouteOptimizer.swift
//  Greedy nearest-neighbor route ordering for the Saved tab's Optimize button.
//
//  Spec: docs/business-logic.md §6 (lines 152–207).
//

import Foundation
import SwiftData

enum NearestNeighbor {
    /// Order the stops greedily by nearest-neighbor distance.
    /// - Parameters:
    ///   - stops: trip stops to reorder
    ///   - startFromUserLocation: if true, start from the user's location; otherwise start from `stops.first`
    ///   - roundTrip: not yet enforced — placeholder for future symmetric optimization
    ///   - userLat/userLng: caller-supplied origin (typically `LocationService.shared.coordinateOrFallback`)
    static func order(
        stops: [TripStop],
        startFromUserLocation: Bool,
        roundTrip: Bool,
        userLat: Double,
        userLng: Double
    ) -> [TripStop] {
        guard stops.count >= 2 else { return stops }

        var remaining = stops
        var ordered: [TripStop] = []

        var currentLat: Double
        var currentLng: Double

        if startFromUserLocation {
            currentLat = userLat
            currentLng = userLng
        } else if let first = remaining.first, let lat = first.lat, let lng = first.lng {
            ordered.append(first)
            remaining.removeFirst()
            currentLat = lat
            currentLng = lng
        } else {
            // No coords available — return as-is.
            return stops
        }

        while !remaining.isEmpty {
            let next = remaining.min { a, b in
                haversine(lat1: currentLat, lng1: currentLng, lat2: a.lat ?? 0, lng2: a.lng ?? 0) <
                haversine(lat1: currentLat, lng1: currentLng, lat2: b.lat ?? 0, lng2: b.lng ?? 0)
            }
            guard let pick = next else { break }
            ordered.append(pick)
            remaining.removeAll { $0.persistentModelID == pick.persistentModelID }
            currentLat = pick.lat ?? currentLat
            currentLng = pick.lng ?? currentLng
        }

        return ordered
    }

    /// Great-circle distance in miles between two coordinates.
    static func haversine(lat1: Double, lng1: Double, lat2: Double, lng2: Double) -> Double {
        let r = 3958.8  // Earth radius in miles
        let dLat = (lat2 - lat1) * .pi / 180
        let dLng = (lng2 - lng1) * .pi / 180
        let lat1R = lat1 * .pi / 180
        let lat2R = lat2 * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
              + sin(dLng / 2) * sin(dLng / 2) * cos(lat1R) * cos(lat2R)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return r * c
    }
}
