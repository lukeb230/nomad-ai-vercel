//
//  Seed.swift
//  First-launch SwiftData seeding so the Saved tab has visible data
//  without requiring the user to bookmark anything from Search first.
//
//  Bumps the `didSeedKey` version when seed shape changes so existing
//  installs can be re-seeded on update.
//

import Foundation
import OSLog
import SwiftData

private let seedLog = Logger(subsystem: "LukeBrowne.NomadAI", category: "seed")

enum Seed {
    /// Bump this string to force a re-seed on next launch.
    /// Internal so `SettingsSheet`'s "Reset all data" can clear it.
    static let didSeedKey = "nomad_did_seed_v1"

    static func seedIfNeeded(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: didSeedKey) else { return }

        // Saved campsites — 8 sites the user has bookmarked.
        let savedSites: [(id: String, name: String, source: CampsiteSource, fee: String, lat: Double, lng: Double, city: String, state: String, tags: [String])] = [
            ("seed-saved-1", "Hickison Petroglyphs", .blm,           "Free",        39.3640, -116.8420, "Austin",        "NV", ["dispersed", "petroglyphs"]),
            ("seed-saved-2", "Ward Mountain BLM",    .blm,           "Free",        39.1490, -114.9050, "Ely",           "NV", ["dispersed"]),
            ("seed-saved-3", "Cathedral Gorge",      .recreationGov, "$20/night",   37.8190, -114.4080, "Panaca",        "NV", ["reservable", "scenic"]),
            ("seed-saved-4", "Valley of Fire West",  .ioverlander,   "Free",        36.4690, -114.6010, "Overton",       "NV", ["dispersed"]),
            ("seed-saved-5", "Sand Flats",           .blm,           "$15/night",   38.5836, -109.5022, "Moab",          "UT", ["dispersed", "4x4"]),
            ("seed-saved-6", "Willow Springs Road",  .ioverlander,   "Free",        38.6630, -109.6772, "Moab",          "UT", ["dispersed", "BLM"]),
            ("seed-saved-7", "Devils Garden CG",     .recreationGov, "$25/night",   38.7814, -109.5733, "Arches NP",     "UT", ["reservable"]),
            ("seed-saved-8", "Lone Mesa Group",      .recreationGov, "$70/group",   38.7095, -109.6014, "Moab",          "UT", ["group"])
        ]

        let now = Date()
        for (i, s) in savedSites.enumerated() {
            let c = Campsite(
                id: s.id,
                name: s.name,
                source: s.source,
                sourceLabel: nil,
                url: nil,
                fee: s.fee,
                reservable: s.tags.contains("reservable"),
                siteDescription: nil,
                tags: s.tags,
                directions: nil,
                lat: s.lat,
                lng: s.lng,
                city: s.city,
                state: s.state,
                seasonal: .yearRound,
                amenities: [],
                fromDatabase: false
            )
            c.isSaved = true
            c.savedAt = now.addingTimeInterval(TimeInterval(-i * 86400))  // staggered over recent days
            context.insert(c)
        }

        // Visited campsites — 5 sites with visitedAt spread over 60 days.
        let visitedSites: [(id: String, name: String, state: String, source: CampsiteSource, daysAgo: Int)] = [
            ("seed-visited-1", "Fallon BLM",           "NV", .blm,           4),
            ("seed-visited-2", "Austin Summit Pass",   "NV", .ioverlander,   12),
            ("seed-visited-3", "Tonopah Wash",         "NV", .blm,           20),
            ("seed-visited-4", "Bonneville Salt Flats","UT", .ioverlander,   34),
            ("seed-visited-5", "Mojave Wilderness",    "CA", .blm,           58)
        ]

        for v in visitedSites {
            let c = Campsite(
                id: v.id,
                name: v.name,
                source: v.source,
                sourceLabel: nil,
                fee: "Free",
                reservable: false,
                siteDescription: nil,
                tags: ["dispersed"],
                lat: nil, lng: nil,
                city: nil, state: v.state,
                seasonal: .yearRound,
                amenities: [],
                fromDatabase: false
            )
            c.isVisited = true
            c.visitedAt = now.addingTimeInterval(TimeInterval(-v.daysAgo * 86400))
            c.rating = Int.random(in: 3...5)
            context.insert(c)
        }

        // One active trip — Carson City → Moab corridor, 5 stops in geographic order.
        let trip = Trip(id: UUID(), startedAt: now.addingTimeInterval(-3 * 86400))
        trip.roundTrip = false
        trip.startFromUserLocation = true
        context.insert(trip)

        let routeStops: [(name: String, campsiteId: String, lat: Double, lng: Double)] = [
            ("Fallon",            "seed-route-1", 39.4735, -118.7773),
            ("Austin Pass",       "seed-route-2", 39.4929, -117.0707),
            ("Hickison Pet.",     "seed-route-3", 39.3640, -116.8420),
            ("Ward Mountain BLM", "seed-route-4", 39.1490, -114.9050),
            ("Moab",              "seed-route-5", 38.5733, -109.5498)
        ]

        for (i, s) in routeStops.enumerated() {
            let stop = TripStop(order: i, campsiteId: s.campsiteId, campsiteName: s.name, lat: s.lat, lng: s.lng)
            stop.trip = trip
            context.insert(stop)
        }

        // Two completed trips for Passport stats.
        context.insert(CompletedTrip(
            id: UUID(),
            completedAt: now.addingTimeInterval(-30 * 86400),
            stopNames: ["Fallon", "Austin", "Tonopah"]
        ))
        context.insert(CompletedTrip(
            id: UUID(),
            completedAt: now.addingTimeInterval(-72 * 86400),
            stopNames: ["Bonneville", "Wendover", "Lucin", "Mojave Wilderness"]
        ))

        do {
            try context.save()
            UserDefaults.standard.set(true, forKey: didSeedKey)
        } catch {
            seedLog.error("seed save failed: \(error.localizedDescription)")
        }
    }
}
