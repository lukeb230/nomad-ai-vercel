//
//  CoordinateValidator.swift
//  Cross-checks Claude's lat/lng for each campsite against Apple's MKLocalSearch.
//  When Apple disagrees by more than 2 miles, we trust Apple — Claude occasionally
//  fabricates coordinates that don't match the named place, which makes the
//  satellite snapshot in SitePhotoView render the wrong location.
//
//  Free + no API key (MKLocalSearch is part of MapKit). Cached per
//  (name, city, state) so the same site is only validated once per process.
//

import Foundation
import CoreLocation
import MapKit
import SwiftData

actor CoordinateValidator {
    static let shared = CoordinateValidator()

    private struct Key: Hashable {
        let name: String
        let city: String
        let state: String
    }

    /// `nil` means MKLocalSearch returned nothing — don't retry this session.
    private var cache: [Key: CLLocationCoordinate2D?] = [:]
    private var inflight: [Key: Task<CLLocationCoordinate2D?, Never>] = [:]

    private init() {}

    /// Returns Apple's coordinate for the named place, or nil if MKLocalSearch
    /// couldn't find a match. Concurrent calls for the same key share one task.
    func appleCoord(name: String, city: String, state: String) async -> CLLocationCoordinate2D? {
        let key = Key(name: name, city: city, state: state)
        if let cached = cache[key] { return cached }
        if let task = inflight[key] { return await task.value }

        let task = Task<CLLocationCoordinate2D?, Never> {
            let req = MKLocalSearch.Request()
            req.naturalLanguageQuery = "\(name), \(city), \(state)"
            do {
                let response = try await MKLocalSearch(request: req).start()
                return response.mapItems.first?.placemark.coordinate
            } catch {
                return nil
            }
        }
        inflight[key] = task
        let result = await task.value
        inflight[key] = nil
        cache[key] = result
        return result
    }

    /// Returns the coord we should trust. If Apple disagrees with Claude by
    /// more than `thresholdMeters`, prefer Apple's. Otherwise keep Claude's.
    func validatedCoord(
        name: String,
        city: String,
        state: String,
        claudeLat: Double,
        claudeLng: Double,
        thresholdMeters: Double = 3219 // 2 miles
    ) async -> CLLocationCoordinate2D {
        let claude = CLLocationCoordinate2D(latitude: claudeLat, longitude: claudeLng)
        guard let apple = await appleCoord(name: name, city: city, state: state) else {
            return claude
        }
        let dMeters = CLLocation(latitude: claudeLat, longitude: claudeLng)
            .distance(from: CLLocation(latitude: apple.latitude, longitude: apple.longitude))
        return dMeters > thresholdMeters ? apple : claude
    }
}

// MARK: - SwiftData helper

/// Snapshots the inputs on the main actor, fans out validation in parallel,
/// then applies coordinate updates on the main actor and saves the context.
/// Skips sites where:
///   - `fromDatabase == true` (RIDB and other authoritative-source sites — their
///     coordinates are trusted upstream, no need to second-guess them).
///   - name/city/state/lat/lng are missing (can't form a useful query).
@MainActor
func validateCoordinates(for sites: [Campsite], in ctx: ModelContext) async {
    struct Snap: Sendable {
        let idx: Int
        let name: String
        let city: String
        let state: String
        let lat: Double
        let lng: Double
    }

    let snapshots: [Snap] = sites.enumerated().compactMap { i, s in
        guard !s.fromDatabase,
              let city = s.city, !city.isEmpty,
              let state = s.state, !state.isEmpty,
              let lat = s.lat, let lng = s.lng else { return nil }
        return Snap(idx: i, name: s.name, city: city, state: state, lat: lat, lng: lng)
    }
    if snapshots.isEmpty { return }

    let updates: [(Int, CLLocationCoordinate2D)] = await withTaskGroup(
        of: (Int, CLLocationCoordinate2D).self
    ) { group in
        for snap in snapshots {
            group.addTask {
                let coord = await CoordinateValidator.shared.validatedCoord(
                    name: snap.name,
                    city: snap.city,
                    state: snap.state,
                    claudeLat: snap.lat,
                    claudeLng: snap.lng
                )
                return (snap.idx, coord)
            }
        }
        var out: [(Int, CLLocationCoordinate2D)] = []
        for await pair in group { out.append(pair) }
        return out
    }

    var dirty = false
    for (idx, coord) in updates {
        let site = sites[idx]
        guard let lat = site.lat, let lng = site.lng else { continue }
        if abs(coord.latitude - lat) > 0.0001 || abs(coord.longitude - lng) > 0.0001 {
            site.lat = coord.latitude
            site.lng = coord.longitude
            site.updatedAt = Date()
            dirty = true
        }
    }
    if dirty { try? ctx.save() }
}
