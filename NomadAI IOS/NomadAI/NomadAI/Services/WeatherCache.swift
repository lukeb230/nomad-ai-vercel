//
//  WeatherCache.swift
//  Caching wrapper around Apple WeatherKit for the CampsiteCard data cells.
//
//  WeatherKit ships with iOS 16+ but requires the WeatherKit capability +
//  entitlement on the App ID. Without it, fetches throw at runtime; the cells
//  remain at "—" and the user sees no error. With the capability added, the
//  free quota is 500K calls/month per Apple Developer account.
//
//  Cache strategy: in-memory dict keyed on campsite.id, 30-min TTL. Weather
//  doesn't need minute-by-minute freshness for a campsite preview, and the
//  TTL keeps us well within free tier even for heavy users.
//

import Foundation
import CoreLocation
import WeatherKit
import OSLog

private let weatherLog = Logger(subsystem: "LukeBrowne.NomadAI", category: "weather")

@Observable
final class WeatherCache {
    static let shared = WeatherCache()

    struct Snapshot {
        let temperatureF: Double
        let conditionDescription: String      // e.g. "Mostly Sunny"
        let conditionSymbol: String            // SF Symbol name from WeatherKit
        let windSpeedMph: Double
        let windDirection: String              // "NW"
        let sunrise: Date?
        let sunset: Date?
        let fetchedAt: Date
    }

    @ObservationIgnored private var cache: [String: Snapshot] = [:]
    @ObservationIgnored private let ttl: TimeInterval = 30 * 60   // 30 min

    private init() {}

    /// Returns a cached snapshot if fresh, otherwise fetches from WeatherKit.
    /// Returns nil on failure (no entitlement, network error, etc.).
    func snapshot(for campsiteId: String, lat: Double, lng: Double) async -> Snapshot? {
        if let s = cache[campsiteId], Date().timeIntervalSince(s.fetchedAt) < ttl {
            return s
        }
        do {
            let loc = CLLocation(latitude: lat, longitude: lng)
            let weather = try await WeatherKit.WeatherService.shared.weather(for: loc)
            let current = weather.currentWeather
            let today = weather.dailyForecast.first { Calendar.current.isDateInToday($0.date) }
                       ?? weather.dailyForecast.first

            let snap = Snapshot(
                temperatureF: current.temperature.converted(to: .fahrenheit).value,
                conditionDescription: current.condition.description,
                conditionSymbol: current.symbolName,
                windSpeedMph: current.wind.speed.converted(to: .milesPerHour).value,
                windDirection: cardinal(from: current.wind.direction.converted(to: .degrees).value),
                sunrise: today?.sun.sunrise,
                sunset: today?.sun.sunset,
                fetchedAt: Date()
            )
            cache[campsiteId] = snap
            weatherLog.notice("WeatherKit hit for \(campsiteId, privacy: .public): \(Int(snap.temperatureF))°F, \(snap.conditionDescription, privacy: .public)")
            return snap
        } catch {
            weatherLog.error("WeatherKit fetch failed for \(campsiteId, privacy: .public): \(error.localizedDescription)")
            return nil
        }
    }

    private func cardinal(from degrees: Double) -> String {
        let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let normalized = (degrees + 22.5).truncatingRemainder(dividingBy: 360)
        let i = Int(normalized / 45) % 8
        return dirs[max(0, min(7, i))]
    }
}
