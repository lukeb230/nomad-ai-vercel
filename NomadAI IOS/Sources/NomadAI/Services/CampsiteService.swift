//
//  CampsiteService.swift
//  NomadAI — Database-first campsite search via /api/search-campsites
//

import Foundation
import CoreLocation

actor CampsiteService {
    static let shared = CampsiteService()

    private let baseURL = URL(string: "https://nomadai.us")!

    /// Search the campsites table. Mirrors `/api/search-campsites`.
    func search(
        lat: Double,
        lng: Double,
        radius: Int = 50,
        limit: Int = 20,
        tags: [String] = [],
        source: String? = nil
    ) async throws -> [CampsiteDTO] {
        var components = URLComponents(url: baseURL.appending(path: "/api/search-campsites"), resolvingAgainstBaseURL: true)!
        var query: [URLQueryItem] = [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lng", value: String(lng)),
            URLQueryItem(name: "radius", value: String(radius)),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if !tags.isEmpty {
            query.append(URLQueryItem(name: "tags", value: tags.joined(separator: ",")))
        }
        if let source {
            query.append(URLQueryItem(name: "source", value: source))
        }
        components.queryItems = query

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        struct Envelope: Codable {
            let sites: [CampsiteDTO]
            let total: Int
            let radius: Int
        }
        let env = try JSONDecoder().decode(Envelope.self, from: data)
        return env.sites
    }
}

// MARK: - Photo fetching via /api/places

actor PlacesService {
    static let shared = PlacesService()
    private let baseURL = URL(string: "https://nomadai.us")!
    private let cache = URLCache(memoryCapacity: 32 * 1024 * 1024, diskCapacity: 200 * 1024 * 1024)

    /// Fetch up to 5 photo references for a campsite name.
    func searchPhotoReferences(for siteName: String) async throws -> [String] {
        var components = URLComponents(url: baseURL.appending(path: "/api/places"), resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "type", value: "search"),
            URLQueryItem(name: "input", value: siteName)
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)

        struct Envelope: Codable {
            let candidates: [Candidate]
            struct Candidate: Codable {
                let photos: [Photo]?
                struct Photo: Codable {
                    let photo_reference: String
                }
            }
        }
        let env = try JSONDecoder().decode(Envelope.self, from: data)
        return env.candidates.first?.photos?.map(\.photo_reference) ?? []
    }

    /// Returns a URL pointing at the proxied photo. Use directly with AsyncImage.
    func photoURL(reference: String) -> URL {
        baseURL
            .appending(path: "/api/places")
            .appending(queryItems: [
                URLQueryItem(name: "type", value: "photo"),
                URLQueryItem(name: "ref", value: reference)
            ])
    }
}

// MARK: - Open-Meteo weather (direct, no proxy)

actor WeatherService {
    static let shared = WeatherService()

    struct Forecast: Codable {
        struct Current: Codable {
            let temperature_2m: Double
            let wind_speed_10m: Double
            let wind_direction_10m: Double
            let weather_code: Int
        }
        struct Daily: Codable {
            let sunrise: [String]   // ISO 8601 strings
            let sunset: [String]
        }
        let current: Current
        let daily: Daily
    }

    func fetch(lat: Double, lng: Double) async throws -> Forecast {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(lat)),
            URLQueryItem(name: "longitude", value: String(lng)),
            URLQueryItem(name: "current", value: "temperature_2m,wind_speed_10m,wind_direction_10m,weather_code"),
            URLQueryItem(name: "daily", value: "sunrise,sunset"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "wind_speed_unit", value: "mph")
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(Forecast.self, from: data)
    }

    /// Map Open-Meteo weather code to a SF Symbol.
    /// See https://open-meteo.com/en/docs#weathervariables.
    static func sfSymbol(forCode code: Int) -> String {
        switch code {
        case 0: return "sun.max"
        case 1, 2, 3: return "cloud.sun"
        case 45, 48: return "cloud.fog"
        case 51...67: return "cloud.rain"
        case 71...77: return "cloud.snow"
        case 80...82: return "cloud.heavyrain"
        case 95...99: return "cloud.bolt.rain"
        default: return "cloud"
        }
    }
}
