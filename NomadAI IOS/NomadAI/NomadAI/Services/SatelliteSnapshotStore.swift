//
//  SatelliteSnapshotStore.swift
//  Process-wide cache for MKMapSnapshotter satellite snapshots.
//
//  Apple's MapKit can render an offline UIImage of a coordinate region using
//  hybrid satellite tiles — no API key, no per-tile cost. We use that as the
//  "always-available" frame for SitePhotoView's carousel: every campsite has
//  a lat/lng, so every campsite has at least a satellite view.
//
//  Cache is in-memory + per-session. A cold launch regenerates; in practice
//  one snapshot per site per session is fine. Phase 9 polish could persist to
//  the caches directory if memory pressure grows.
//

import Foundation
import MapKit
import UIKit

@Observable
final class SatelliteSnapshotStore {
    static let shared = SatelliteSnapshotStore()

    @ObservationIgnored private var cache: [String: UIImage] = [:]
    @ObservationIgnored private var inflight: [String: Task<UIImage?, Never>] = [:]

    private init() {}

    /// Returns a hybrid satellite snapshot for the given coordinate, or nil on failure.
    /// Subsequent calls with the same key hit the in-memory cache.
    func snapshot(lat: Double, lng: Double, size: CGSize) async -> UIImage? {
        let key = "\(lat),\(lng),\(Int(size.width))x\(Int(size.height))"
        if let cached = cache[key] { return cached }
        if let task = inflight[key] { return await task.value }

        let task = Task<UIImage?, Never> {
            let options = MKMapSnapshotter.Options()
            options.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
            options.size = size
            options.mapType = .satellite
            let snapshotter = MKMapSnapshotter(options: options)
            do {
                let snapshot = try await snapshotter.start()
                return snapshot.image
            } catch {
                return nil
            }
        }
        inflight[key] = task
        let result = await task.value
        inflight[key] = nil
        if let img = result { cache[key] = img }
        return result
    }
}
