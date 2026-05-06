//
//  MockData.swift
//  Sample data so we can render Home + Map pixel-perfect without wiring SwiftData yet.
//
//  Lifted from `NomadAI Redesign.html` lines 1416–1591 to match the canonical
//  visual reference exactly.
//

import Foundation
import CoreLocation

// MARK: - Mock trip

struct MockStop: Identifiable, Hashable {
    let id = UUID()
    let n: Int
    let name: String
    let state: MockStop.Status

    enum Status: Hashable { case done, next, future }
}

struct MockTrip {
    let title: String                  // "Carson City → Moab"
    let totalMiles: String             // "1,247 mi"
    let stopCount: String              // "8 stops"
    let corridor: String               // "US-50 · BLM corridor"
    let dayOfTotal: String             // "Day 3 of 8"
    let stops: [MockStop]
    let progressPercent: Int           // 0...100

    static let sample = MockTrip(
        title: "Carson City → Moab",
        totalMiles: "1,247 mi",
        stopCount: "8 stops",
        corridor: "US-50 · BLM corridor",
        dayOfTotal: "Day 3 of 8",
        stops: [
            MockStop(n: 1, name: "Fallon",            state: .done),
            MockStop(n: 2, name: "Austin Pass",       state: .done),
            MockStop(n: 3, name: "Hickison Pet.",     state: .done),
            MockStop(n: 4, name: "Ward Mtn (tonight)", state: .next),
            MockStop(n: 5, name: "Cathedral Gorge",   state: .future),
            MockStop(n: 6, name: "Valley of Fire",    state: .future),
            MockStop(n: 7, name: "Valley of the Gods", state: .future),
            MockStop(n: 8, name: "Moab",              state: .future),
        ],
        progressPercent: 42
    )
}

// MARK: - Mock journal entries

struct MockJournalEntry: Identifiable {
    let id = UUID()
    let name: String
    let location: String                  // "Nevada" or "Nevada · Free · BLM"
    let kind: Kind                        // for picking a thumbnail style
    let stars: Int?                       // nil = no rating; else 1...5
    let metaSuffix: String?               // optional extra meta text after location
    let aside: String                     // "2d ago"

    enum Kind { case desert, sky, canyon }

    static let samples: [MockJournalEntry] = [
        MockJournalEntry(
            name: "Hickison Petroglyphs",
            location: "Nevada",
            kind: .desert,
            stars: 4,
            metaSuffix: nil,
            aside: "2d ago"
        ),
        MockJournalEntry(
            name: "Austin Summit Pass",
            location: "Nevada",
            kind: .sky,
            stars: nil,
            metaSuffix: "No fee · Pit toilet",
            aside: "3d ago"
        ),
        MockJournalEntry(
            name: "Fallon BLM Dispersed",
            location: "Nevada",
            kind: .canyon,
            stars: nil,
            metaSuffix: "Windy — air down at turn-in",
            aside: "4d ago"
        ),
    ]
}

// MARK: - Mock route coordinates (Carson City → Moab via US-50)
//
// Lat/lng for each MockTrip stop, in the same order. Used by Map's Route mode
// to draw the dashed polyline + place stop markers.

struct MockRouteStop: Identifiable, Hashable {
    let id = UUID()
    let n: Int
    let name: String
    let state: MockStop.Status
    let lat: Double
    let lng: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

extension MockTrip {
    static let sampleRouteStops: [MockRouteStop] = [
        MockRouteStop(n: 1, name: "Fallon",             state: .done,   lat: 39.4735, lng: -118.7773),
        MockRouteStop(n: 2, name: "Austin Pass",        state: .done,   lat: 39.4929, lng: -117.0707),
        MockRouteStop(n: 3, name: "Hickison Pet.",      state: .done,   lat: 39.3640, lng: -116.8420),
        MockRouteStop(n: 4, name: "Ward Mtn (tonight)", state: .next,   lat: 39.1490, lng: -114.9050),
        MockRouteStop(n: 5, name: "Cathedral Gorge",    state: .future, lat: 37.8190, lng: -114.4080),
        MockRouteStop(n: 6, name: "Valley of Fire",     state: .future, lat: 36.4690, lng: -114.6010),
        MockRouteStop(n: 7, name: "Valley of the Gods", state: .future, lat: 37.2580, lng: -109.8490),
        MockRouteStop(n: 8, name: "Moab",               state: .future, lat: 38.5733, lng: -109.5498)
    ]
}

// MARK: - Mock stats

struct MockStats {
    let visited: Int
    let trips: Int
    let states: Int

    static let sample = MockStats(visited: 24, trips: 7, states: 11)
}
