//
//  Models.swift
//  NomadAI — Persistent + transient data models
//
//  See docs/state-model.md for the full mapping from web localStorage to these types.
//

import Foundation
import SwiftData

// MARK: - Campsite

@Model
final class Campsite {
    @Attribute(.unique) var id: String
    var name: String
    var sourceRaw: String           // CampsiteSource.rawValue
    var sourceLabel: String
    var url: String?
    var fee: String?                // "Free" | "$22/night" | "Unknown"
    var reservable: Bool
    var siteDescription: String?
    var tags: [String]
    var directions: String?
    var lat: Double?
    var lng: Double?
    var city: String?
    var state: String?
    var seasonalRaw: String         // SeasonalAvailability.rawValue
    var amenities: [String]
    var fromDatabase: Bool          // true if returned by /api/search-campsites

    // User-attached state
    var isSaved: Bool = false
    var isVisited: Bool = false
    var savedAt: Date?
    var visitedAt: Date?
    var rating: Int?                // 1...5
    var note: String?

    init(
        id: String,
        name: String,
        source: CampsiteSource = .other,
        sourceLabel: String? = nil,
        url: String? = nil,
        fee: String? = nil,
        reservable: Bool = false,
        siteDescription: String? = nil,
        tags: [String] = [],
        directions: String? = nil,
        lat: Double? = nil,
        lng: Double? = nil,
        city: String? = nil,
        state: String? = nil,
        seasonal: SeasonalAvailability = .unknown,
        amenities: [String] = [],
        fromDatabase: Bool = false
    ) {
        self.id = id
        self.name = name
        self.sourceRaw = source.rawValue
        self.sourceLabel = sourceLabel ?? source.label
        self.url = url
        self.fee = fee
        self.reservable = reservable
        self.siteDescription = siteDescription
        self.tags = tags
        self.directions = directions
        self.lat = lat
        self.lng = lng
        self.city = city
        self.state = state
        self.seasonalRaw = seasonal.rawValue
        self.amenities = amenities
        self.fromDatabase = fromDatabase
    }

    var source: CampsiteSource {
        get { CampsiteSource(rawValue: sourceRaw) ?? .other }
        set { sourceRaw = newValue.rawValue }
    }

    var seasonal: SeasonalAvailability {
        get { SeasonalAvailability(rawValue: seasonalRaw) ?? .unknown }
        set { seasonalRaw = newValue.rawValue }
    }
}

enum SeasonalAvailability: String, Codable, CaseIterable {
    case yearRound = "year-round"
    case summerOnly = "summer-only"
    case winterClosed = "winter-closed"
    case springFall = "spring-fall"
    case unknown
}

// MARK: - Trip

@Model
final class Trip {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var completedAt: Date?
    @Relationship(deleteRule: .cascade, inverse: \TripStop.trip) var stops: [TripStop]
    var currentStopIndex: Int = 0
    var roundTrip: Bool = false
    var startFromUserLocation: Bool = true
    var shareId: String?            // Supabase row id, used for share-link URLs

    init(id: UUID = UUID(), startedAt: Date = Date()) {
        self.id = id
        self.startedAt = startedAt
        self.stops = []
    }

    /// Stops sorted by user-defined order
    var sortedStops: [TripStop] {
        stops.sorted { $0.order < $1.order }
    }
}

@Model
final class TripStop {
    var trip: Trip?
    var order: Int
    var campsiteId: String          // ref to Campsite.id
    var campsiteName: String        // denormalized for display when Campsite is missing
    var lat: Double?
    var lng: Double?
    var scheduledDate: Date?

    init(order: Int, campsiteId: String, campsiteName: String, lat: Double? = nil, lng: Double? = nil) {
        self.order = order
        self.campsiteId = campsiteId
        self.campsiteName = campsiteName
        self.lat = lat
        self.lng = lng
    }
}

// MARK: - Completed Trip (for passport stats)

@Model
final class CompletedTrip {
    @Attribute(.unique) var id: UUID
    var completedAt: Date
    var stopNames: [String]
    var stopCount: Int

    init(id: UUID = UUID(), completedAt: Date = Date(), stopNames: [String]) {
        self.id = id
        self.completedAt = completedAt
        self.stopNames = stopNames
        self.stopCount = stopNames.count
    }
}

// MARK: - Profile (singleton-style)

@Model
final class Profile {
    @Attribute(.unique) var userId: String
    var name: String?
    var avatarURL: String?
    var email: String?

    init(userId: String, name: String? = nil, avatarURL: String? = nil, email: String? = nil) {
        self.userId = userId
        self.name = name
        self.avatarURL = avatarURL
        self.email = email
    }
}

// MARK: - Codable bridge for /api/search-campsites & /api/claude responses

/// Plain Codable struct for decoding JSON from the wire.
/// Convert into a `Campsite` SwiftData model when persisting.
struct CampsiteDTO: Codable, Identifiable {
    var id: String { name + (city ?? "") + (state ?? "") }   // synthesize stable-ish id
    let name: String
    let source: String
    let sourceLabel: String?
    let url: String?
    let distance: String?
    let fee: String?
    let reservable: Bool?
    let description: String?
    let tags: [String]?
    let directions: String?
    let coordinates: Coordinates?
    let city: String?
    let state: String?
    let seasonal: String?
    let views: [String]?
    let amenities: [String]?
    let fromDatabase: Bool?

    private enum CodingKeys: String, CodingKey {
        case name, source, sourceLabel, url, distance, fee, reservable
        case description, tags, directions, coordinates, city, state
        case seasonal, views, amenities
        case fromDatabase = "_fromDatabase"
    }

    struct Coordinates: Codable {
        let lat: Double
        let lng: Double
    }

    /// Build a SwiftData `Campsite` from this DTO.
    func toModel() -> Campsite {
        Campsite(
            id: id,
            name: name,
            source: CampsiteSource(rawValue: source) ?? .other,
            sourceLabel: sourceLabel,
            url: url,
            fee: fee,
            reservable: reservable ?? false,
            siteDescription: description,
            tags: tags ?? [],
            directions: directions,
            lat: coordinates?.lat,
            lng: coordinates?.lng,
            city: city,
            state: state,
            seasonal: SeasonalAvailability(rawValue: seasonal ?? "unknown") ?? .unknown,
            amenities: amenities ?? [],
            fromDatabase: fromDatabase ?? false
        )
    }
}
