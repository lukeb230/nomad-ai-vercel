//
//  LocationService.swift
//  CoreLocation wrapper + process-wide observable user-location store.
//
//  - One singleton holds the current coordinate and auth status, observed by
//    SearchView/SavedView/RouteOptimizer call sites.
//  - Permission is requested lazily, on the first call to `requestLocation()`
//    (driven by the Search tab's "Near me" button).
//  - When unavailable (notDetermined / denied / restricted), `coordinateOrFallback`
//    returns Moab as a graceful fallback so the app keeps working.
//

import Foundation
import CoreLocation
import Observation

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    /// Moab, UT — fallback when the user's location is unknown or denied.
    static let fallback = CLLocationCoordinate2D(latitude: 38.5733, longitude: -109.5498)

    private(set) var coordinate: CLLocationCoordinate2D?
    private(set) var authStatus: CLAuthorizationStatus = .notDetermined

    enum Failure: Error { case denied, restricted, unknown }

    var coordinateOrFallback: CLLocationCoordinate2D {
        coordinate ?? Self.fallback
    }

    var isDenied: Bool {
        authStatus == .denied || authStatus == .restricted
    }

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var pendingContinuations: [CheckedContinuation<CLLocationCoordinate2D, Error>] = []

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authStatus = manager.authorizationStatus
    }

    /// Prompts for permission if needed, then resolves the user's coordinate once.
    /// Throws `Failure.denied` / `.restricted` when permission is unavailable.
    func requestLocation() async throws -> CLLocationCoordinate2D {
        switch authStatus {
        case .denied:
            throw Failure.denied
        case .restricted:
            throw Failure.restricted
        case .notDetermined:
            return try await withCheckedThrowingContinuation { cont in
                pendingContinuations.append(cont)
                manager.requestWhenInUseAuthorization()
                // didChangeAuthorization → either calls requestLocation() on grant
                // or flushes failure on denial.
            }
        case .authorizedWhenInUse, .authorizedAlways:
            return try await withCheckedThrowingContinuation { cont in
                pendingContinuations.append(cont)
                manager.requestLocation()
            }
        @unknown default:
            throw Failure.unknown
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        coordinate = loc.coordinate
        flushSuccess(loc.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        flushFailure(error)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        authStatus = status
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied:
            flushFailure(Failure.denied)
        case .restricted:
            flushFailure(Failure.restricted)
        default:
            break
        }
    }

    private func flushSuccess(_ c: CLLocationCoordinate2D) {
        let conts = pendingContinuations
        pendingContinuations.removeAll()
        for cont in conts { cont.resume(returning: c) }
    }

    private func flushFailure(_ err: Error) {
        let conts = pendingContinuations
        pendingContinuations.removeAll()
        for cont in conts { cont.resume(throwing: err) }
    }
}
