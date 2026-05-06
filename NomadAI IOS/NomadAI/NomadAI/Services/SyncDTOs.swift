//
//  SyncDTOs.swift
//  Codable wire types mirroring the four Supabase tables in the iOS project.
//
//  Property names use camelCase; the Supabase Swift SDK's default JSONEncoder
//  applies `.convertToSnakeCase` so `userId` → `user_id` etc. on the wire.
//
//  Each row exposes:
//    - init(from: <Model>, userId:) — local → wire
//    - apply(to: <Model>)            — wire → local
//

import Foundation
import SwiftData

// MARK: - Profile

struct ProfileRow: Codable, Sendable {
    let userId: String
    var name: String?
    var avatarUrl: String?
    var email: String?
    var updatedAt: Date

    init(from p: Profile) {
        self.userId = p.userId
        self.name = p.name
        self.avatarUrl = p.avatarURL
        self.email = p.email
        self.updatedAt = p.updatedAt ?? Date()
    }

    func apply(to p: Profile) {
        p.name = name
        p.avatarURL = avatarUrl
        p.email = email
        p.updatedAt = updatedAt
    }
}

// MARK: - Campsite (denormalized: static + user state)

struct CampsiteRow: Codable, Sendable {
    let userId: String
    let campsiteId: String
    // static
    var name: String
    var sourceRaw: String?
    var sourceLabel: String?
    var url: String?
    var fee: String?
    var reservable: Bool?
    var siteDescription: String?
    var tags: [String]?
    var directions: String?
    var lat: Double?
    var lng: Double?
    var city: String?
    var state: String?
    var seasonalRaw: String?
    var amenities: [String]?
    var photoReferences: [String]?
    // user state
    var isSaved: Bool
    var isVisited: Bool
    var savedAt: Date?
    var visitedAt: Date?
    var rating: Int?
    var note: String?
    var updatedAt: Date

    init(from c: Campsite, userId: String) {
        self.userId = userId
        self.campsiteId = c.id
        self.name = c.name
        self.sourceRaw = c.sourceRaw
        self.sourceLabel = c.sourceLabel
        self.url = c.url
        self.fee = c.fee
        self.reservable = c.reservable
        self.siteDescription = c.siteDescription
        self.tags = c.tags
        self.directions = c.directions
        self.lat = c.lat
        self.lng = c.lng
        self.city = c.city
        self.state = c.state
        self.seasonalRaw = c.seasonalRaw
        self.amenities = c.amenities
        self.photoReferences = c.photoReferences
        self.isSaved = c.isSaved
        self.isVisited = c.isVisited
        self.savedAt = c.savedAt
        self.visitedAt = c.visitedAt
        self.rating = c.rating
        self.note = c.note
        self.updatedAt = c.updatedAt ?? Date()
    }

    /// Apply remote → local. Static fields update unconditionally; user state always copies.
    func apply(to c: Campsite) {
        c.name = name
        if let s = sourceRaw { c.sourceRaw = s }
        if let s = sourceLabel { c.sourceLabel = s }
        c.url = url
        c.fee = fee
        if let r = reservable { c.reservable = r }
        c.siteDescription = siteDescription
        if let t = tags { c.tags = t }
        c.directions = directions
        c.lat = lat
        c.lng = lng
        c.city = city
        c.state = state
        if let s = seasonalRaw { c.seasonalRaw = s }
        if let a = amenities { c.amenities = a }
        // photoReferences only sync when the remote actually has a value — preserve local cache otherwise.
        if let refs = photoReferences { c.photoReferences = refs }
        c.isSaved = isSaved
        c.isVisited = isVisited
        c.savedAt = savedAt
        c.visitedAt = visitedAt
        c.rating = rating
        c.note = note
        c.updatedAt = updatedAt
    }

    /// Build a brand-new local Campsite from this row (when no local exists yet).
    func toModel() -> Campsite {
        Campsite(
            id: campsiteId,
            name: name,
            source: CampsiteSource(rawValue: sourceRaw ?? "") ?? .other,
            sourceLabel: sourceLabel,
            url: url,
            fee: fee,
            reservable: reservable ?? false,
            siteDescription: siteDescription,
            tags: tags ?? [],
            directions: directions,
            lat: lat,
            lng: lng,
            city: city,
            state: state,
            seasonal: SeasonalAvailability(rawValue: seasonalRaw ?? "unknown") ?? .unknown,
            amenities: amenities ?? [],
            fromDatabase: false,
            photoReference: nil,
            photoReferences: photoReferences,
            updatedAt: updatedAt
        ).apply { c in
            c.isSaved = isSaved
            c.isVisited = isVisited
            c.savedAt = savedAt
            c.visitedAt = visitedAt
            c.rating = rating
            c.note = note
        }
    }
}

// MARK: - Trip (with stops embedded as jsonb)

struct TripStopJSON: Codable, Sendable {
    let order: Int
    let campsiteId: String
    let campsiteName: String
    let lat: Double?
    let lng: Double?
    let scheduledDate: Date?

    init(from s: TripStop) {
        self.order = s.order
        self.campsiteId = s.campsiteId
        self.campsiteName = s.campsiteName
        self.lat = s.lat
        self.lng = s.lng
        self.scheduledDate = s.scheduledDate
    }

    func toModel() -> TripStop {
        TripStop(order: order, campsiteId: campsiteId, campsiteName: campsiteName, lat: lat, lng: lng)
    }
}

struct TripRow: Codable, Sendable {
    let id: UUID
    let userId: String
    var name: String?
    var isActive: Bool
    var startedAt: Date
    var completedAt: Date?
    var currentStopIndex: Int
    var roundTrip: Bool
    var startFromUserLocation: Bool
    var shareId: String?
    var stops: [TripStopJSON]
    var updatedAt: Date

    init(from t: Trip, userId: String) {
        self.id = t.id
        self.userId = userId
        self.name = t.name
        self.isActive = t.isActive
        self.startedAt = t.startedAt
        self.completedAt = t.completedAt
        self.currentStopIndex = t.currentStopIndex
        self.roundTrip = t.roundTrip
        self.startFromUserLocation = t.startFromUserLocation
        self.shareId = t.shareId
        self.stops = t.sortedStops.map(TripStopJSON.init)
        self.updatedAt = t.updatedAt ?? Date()
    }

    /// Apply remote → local. Trip's stops are nuked + recreated from `stops`.
    func apply(to t: Trip, in ctx: ModelContext) {
        t.name = name
        t.isActive = isActive
        t.startedAt = startedAt
        t.completedAt = completedAt
        t.currentStopIndex = currentStopIndex
        t.roundTrip = roundTrip
        t.startFromUserLocation = startFromUserLocation
        t.shareId = shareId
        t.updatedAt = updatedAt
        // Replace stops wholesale. SwiftData's cascade handles deletion of orphans.
        for stop in t.stops {
            ctx.delete(stop)
        }
        for stopJSON in stops {
            let stop = stopJSON.toModel()
            stop.trip = t
            ctx.insert(stop)
        }
    }

    func toModel(in ctx: ModelContext) -> Trip {
        let trip = Trip(id: id, startedAt: startedAt)
        trip.name = name
        trip.isActive = isActive
        trip.completedAt = completedAt
        trip.currentStopIndex = currentStopIndex
        trip.roundTrip = roundTrip
        trip.startFromUserLocation = startFromUserLocation
        trip.shareId = shareId
        trip.updatedAt = updatedAt
        for stopJSON in stops {
            let stop = stopJSON.toModel()
            stop.trip = trip
            ctx.insert(stop)
        }
        return trip
    }
}

// MARK: - CompletedTrip

struct CompletedTripRow: Codable, Sendable {
    let id: UUID
    let userId: String
    var completedAt: Date
    var stopNames: [String]
    var stopCount: Int
    var updatedAt: Date

    init(from c: CompletedTrip, userId: String) {
        self.id = c.id
        self.userId = userId
        self.completedAt = c.completedAt
        self.stopNames = c.stopNames
        self.stopCount = c.stopCount
        self.updatedAt = c.updatedAt ?? Date()
    }

    func apply(to c: CompletedTrip) {
        c.completedAt = completedAt
        c.stopNames = stopNames
        c.stopCount = stopCount
        c.updatedAt = updatedAt
    }

    func toModel() -> CompletedTrip {
        let ct = CompletedTrip(id: id, completedAt: completedAt, stopNames: stopNames, updatedAt: updatedAt)
        return ct
    }
}

// MARK: - Tiny helper used by CampsiteRow.toModel

private extension Campsite {
    func apply(_ block: (Campsite) -> Void) -> Campsite {
        block(self)
        return self
    }
}
