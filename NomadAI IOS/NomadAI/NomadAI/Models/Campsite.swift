//
//  Models.swift
//  NomadAI — Persistent + transient data models
//
//  See docs/state-model.md for the full mapping from web localStorage to these types.
//

import Foundation
import SwiftData
import CoreLocation

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
    /// Stable identifier from the upstream source (RIDB FacilityID, OSM
    /// element id, etc.). Lets us synthesize canonical Source URLs like
    /// `recreation.gov/camping/campgrounds/<id>` when the upstream record
    /// didn't include a usable `url`. nil for Claude-returned sites.
    var externalId: String?

    // User-attached state
    var isSaved: Bool = false
    var isVisited: Bool = false
    var savedAt: Date?
    var visitedAt: Date?
    var rating: Int?                // 1...5
    var note: String?

    /// Deprecated — superseded by `photoReferences`. Kept to avoid a SwiftData migration.
    /// nil = never looked up. "" = looked up, none found.
    var photoReference: String?

    /// Google Places photo references (up to 5). nil = never looked up. [] = looked up, none found.
    var photoReferences: [String]?

    /// Last user-edit timestamp. Drives last-write-wins sync. nil = never edited.
    var updatedAt: Date?

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
        fromDatabase: Bool = false,
        externalId: String? = nil,
        photoReference: String? = nil,
        photoReferences: [String]? = nil,
        updatedAt: Date? = nil
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
        self.externalId = externalId
        self.photoReference = photoReference
        self.photoReferences = photoReferences
        self.updatedAt = updatedAt
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

    /// Optional user-set name for the trip. When nil, `displayName` falls back
    /// to "First stop → Last stop" derived from the route. Lets users have
    /// multiple trips simultaneously without renaming each one immediately.
    var name: String?

    /// User-pinned "active" trip. At most one Trip in the database has this set
    /// to true at any time (enforced by `Trip.setActive`). Drives Home tab's
    /// hero card, Map's Route mode default, and Saved tab's picker default.
    /// nil treated as false — older synced trips don't need migration.
    var isActive: Bool = false

    /// Last edit timestamp. Drives last-write-wins sync.
    var updatedAt: Date?

    init(id: UUID = UUID(), startedAt: Date = Date()) {
        self.id = id
        self.startedAt = startedAt
        self.stops = []
    }

    /// Stops sorted by user-defined order
    var sortedStops: [TripStop] {
        stops.sorted { $0.order < $1.order }
    }

    /// Human-readable label for the trip — explicit `name` if set, else
    /// derived from the first → last stop name, else a generic placeholder.
    var displayName: String {
        if let n = name?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
            return n
        }
        let stops = sortedStops
        if stops.count >= 2,
           let first = stops.first?.campsiteName, !first.isEmpty,
           let last = stops.last?.campsiteName, !last.isEmpty,
           first != last {
            return "\(first) → \(last)"
        }
        if let only = stops.first?.campsiteName, !only.isEmpty {
            return only
        }
        return "Untitled trip"
    }

    /// Pin one trip as the user's "active" trip — exclusive flag, at most one
    /// trip is active at a time. Clears `isActive` on any other trip first to
    /// maintain the invariant, then saves the context.
    static func setActive(_ trip: Trip, in ctx: ModelContext) {
        let fetch = FetchDescriptor<Trip>(predicate: #Predicate { $0.isActive == true })
        if let others = try? ctx.fetch(fetch) {
            for other in others where other.id != trip.id {
                other.isActive = false
                other.updatedAt = Date()
            }
        }
        trip.isActive = true
        trip.updatedAt = Date()
        try? ctx.save()
    }

    /// Unpin this trip from active. No-op if it wasn't active.
    static func clearActive(_ trip: Trip, in ctx: ModelContext) {
        guard trip.isActive else { return }
        trip.isActive = false
        trip.updatedAt = Date()
        try? ctx.save()
    }

    /// Full coordinate sequence to draw / measure for this trip:
    /// optionally prefixed with the user's location (if `startFromUserLocation`)
    /// and/or suffixed with the start to close the loop (if `roundTrip`).
    /// Stops missing lat/lng are skipped. Used by the map polyline (Map tab and
    /// Home hero), total-miles math, and the round-trip leg label in Saved.
    func routeCoordSequence(userLat: Double, userLng: Double) -> [CLLocationCoordinate2D] {
        var coords: [CLLocationCoordinate2D] = []
        if startFromUserLocation {
            coords.append(CLLocationCoordinate2D(latitude: userLat, longitude: userLng))
        }
        for stop in sortedStops {
            if let lat = stop.lat, let lng = stop.lng {
                coords.append(CLLocationCoordinate2D(latitude: lat, longitude: lng))
            }
        }
        if roundTrip, let first = coords.first {
            coords.append(first)
        }
        return coords
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

    /// Last edit timestamp. Drives last-write-wins sync.
    var updatedAt: Date?

    init(id: UUID = UUID(), completedAt: Date = Date(), stopNames: [String], updatedAt: Date? = nil) {
        self.id = id
        self.completedAt = completedAt
        self.stopNames = stopNames
        self.stopCount = stopNames.count
        self.updatedAt = updatedAt
    }
}

// MARK: - Profile (singleton-style)

@Model
final class Profile {
    @Attribute(.unique) var userId: String
    var name: String?
    var avatarURL: String?
    var email: String?

    /// Last edit timestamp. Drives last-write-wins sync.
    var updatedAt: Date?

    init(userId: String, name: String? = nil, avatarURL: String? = nil, email: String? = nil, updatedAt: Date? = nil) {
        self.userId = userId
        self.name = name
        self.avatarURL = avatarURL
        self.email = email
        self.updatedAt = updatedAt
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
    /// Upstream identifier — RIDB FacilityID, OSM element id, etc. Used by
    /// SourceURLResolver to build canonical reservation links when the
    /// row's `url` is missing. nil for Claude-returned sites.
    let externalId: String?

    private enum CodingKeys: String, CodingKey {
        case name, source, sourceLabel, url, distance, fee, reservable
        case description, tags, directions, coordinates, city, state
        case seasonal, views, amenities
        case fromDatabase = "_fromDatabase"
        case externalId = "_externalId"
    }

    struct Coordinates: Codable {
        let lat: Double
        let lng: Double

        // Tolerant decoder — Claude occasionally emits lat/lng as numeric strings.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            lat = try Self.flexDouble(c, .lat)
            lng = try Self.flexDouble(c, .lng)
        }

        private enum CodingKeys: String, CodingKey { case lat, lng }

        private static func flexDouble(_ c: KeyedDecodingContainer<CodingKeys>, _ k: CodingKeys) throws -> Double {
            if let d = try? c.decode(Double.self, forKey: k) { return d }
            if let s = try? c.decode(String.self, forKey: k), let d = Double(s) { return d }
            throw DecodingError.typeMismatch(
                Double.self,
                .init(codingPath: c.codingPath + [k], debugDescription: "Expected Double or numeric String for \(k.stringValue)")
            )
        }
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
            fromDatabase: fromDatabase ?? false,
            externalId: externalId
        )
    }
}

// MARK: - Upsert helper

extension Campsite {
    /// Insert a new Campsite from the wire, OR if one with the same id exists,
    /// update its discoverable fields while preserving user state (isSaved,
    /// isVisited, timestamps, rating, note).
    @discardableResult
    static func upsert(from dto: CampsiteDTO, into ctx: ModelContext) -> Campsite {
        let id = dto.id
        let fetch = FetchDescriptor<Campsite>(predicate: #Predicate { $0.id == id })
        if let existing = try? ctx.fetch(fetch).first {
            existing.name = dto.name
            existing.sourceRaw = dto.source
            if let label = dto.sourceLabel { existing.sourceLabel = label }
            existing.url = dto.url
            existing.fee = dto.fee
            if let r = dto.reservable { existing.reservable = r }
            existing.siteDescription = dto.description
            if let t = dto.tags { existing.tags = t }
            existing.directions = dto.directions
            if let lat = dto.coordinates?.lat { existing.lat = lat }
            if let lng = dto.coordinates?.lng { existing.lng = lng }
            existing.city = dto.city
            existing.state = dto.state
            if let s = dto.seasonal { existing.seasonalRaw = s }
            if let a = dto.amenities { existing.amenities = a }
            if let fdb = dto.fromDatabase { existing.fromDatabase = fdb }
            // Only adopt a non-empty externalId — preserves a previously-set
            // RIDB FacilityID if Claude later upserts the same site without
            // one (Claude doesn't know our internal ids).
            if let ext = dto.externalId, !ext.isEmpty { existing.externalId = ext }
            return existing
        } else {
            let new = dto.toModel()
            ctx.insert(new)
            return new
        }
    }
}
