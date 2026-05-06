//
//  RouteFetcher.swift
//  Fan-out MKDirections fetcher that stitches per-segment driving routes
//  into a single coordinate sequence so a `MapPolyline` follows actual roads.
//
//  Process-wide cache keyed by the rounded coord sequence so multiple views
//  that show the same trip don't refetch.
//

import Foundation
import MapKit

enum RouteFetcher {
    /// Cache of stitched routes, keyed by rounded coordinate string.
    private static var cache: [String: [CLLocationCoordinate2D]] = [:]
    private static let cacheLock = NSLock()

    /// Returns a stitched road-following route through the given coords.
    /// On partial failure, falls back to straight-line for the failing segment.
    /// On total failure, returns the input unchanged.
    static func driving(through coords: [CLLocationCoordinate2D]) async -> [CLLocationCoordinate2D] {
        guard coords.count >= 2 else { return coords }

        let key = cacheKey(for: coords)
        cacheLock.lock()
        if let hit = cache[key] {
            cacheLock.unlock()
            return hit
        }
        cacheLock.unlock()

        let assembled = await fetch(coords: coords)
        let result = assembled.isEmpty ? coords : assembled

        cacheLock.lock()
        cache[key] = result
        cacheLock.unlock()

        return result
    }

    private static func cacheKey(for coords: [CLLocationCoordinate2D]) -> String {
        coords.map { String(format: "%.4f,%.4f", $0.latitude, $0.longitude) }
              .joined(separator: "|")
    }

    private static func fetch(coords: [CLLocationCoordinate2D]) async -> [CLLocationCoordinate2D] {
        let pairs = (0..<(coords.count - 1)).map { (i: $0, from: coords[$0], to: coords[$0 + 1]) }

        let segments = await withTaskGroup(of: (Int, [CLLocationCoordinate2D]).self) { group -> [(Int, [CLLocationCoordinate2D])] in
            for p in pairs {
                group.addTask {
                    let req = MKDirections.Request()
                    req.source = MKMapItem(placemark: MKPlacemark(coordinate: p.from))
                    req.destination = MKMapItem(placemark: MKPlacemark(coordinate: p.to))
                    req.transportType = .automobile
                    do {
                        let resp = try await MKDirections(request: req).calculate()
                        if let route = resp.routes.first {
                            let pl = route.polyline
                            let n = pl.pointCount
                            var pts = Array(repeating: CLLocationCoordinate2D(), count: n)
                            pl.getCoordinates(&pts, range: NSRange(location: 0, length: n))
                            return (p.i, pts)
                        }
                    } catch {
                        // Per-segment fallback below.
                    }
                    return (p.i, [p.from, p.to])
                }
            }
            var collected: [(Int, [CLLocationCoordinate2D])] = []
            for await r in group { collected.append(r) }
            return collected.sorted { $0.0 < $1.0 }
        }

        // Stitch — drop each segment's first point after the first to avoid duplicates.
        var assembled: [CLLocationCoordinate2D] = []
        for (i, seg) in segments {
            if i == 0 {
                assembled.append(contentsOf: seg)
            } else {
                assembled.append(contentsOf: seg.dropFirst())
            }
        }
        return assembled
    }
}
