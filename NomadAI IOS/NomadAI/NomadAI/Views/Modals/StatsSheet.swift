//
//  StatsSheet.swift
//  Bottom-sheet stats view: visited / saved / states / trips / miles.
//  Settings → Your stats target.
//

import SwiftUI
import SwiftData

struct StatsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Campsite> { $0.isVisited == true })
    private var visited: [Campsite]

    @Query(filter: #Predicate<Campsite> { $0.isSaved == true })
    private var saved: [Campsite]

    @Query private var allTrips: [Trip]
    @Query private var completed: [CompletedTrip]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    grid
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, Spacing.pageHorizontal)
                .padding(.top, 12)
            }
            .background(Color.bg)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .navigationTitle("Your stats")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Field passport").monoLabel()
            FrauncesEmphasis(prefix: "Your campsites in ", italic: "numbers", suffix: ".", size: 24)
                .foregroundStyle(.fg)
            Text("A live snapshot from your local data.")
                .font(.body(13))
                .foregroundStyle(.muted)
        }
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            StatGridCard(value: "\(visited.count)", label: "Visited", icon: "checkmark.seal", color: .moss)
            StatGridCard(value: "\(saved.count)", label: "Saved", icon: "bookmark.fill", color: .clay)
            StatGridCard(value: "\(uniqueStates)", label: "States", icon: "map", color: .rust)
            StatGridCard(value: "\(completed.count)", label: "Completed trips", icon: "flag.fill", color: .slate)
            StatGridCard(value: formatMiles(activeTripMiles), label: "Active trip", icon: "location.north", color: .sand, suffix: "mi")
            StatGridCard(value: formatMiles(totalTripMiles), label: "Total miles", icon: "infinity", color: .berry, suffix: "mi")
        }
    }

    // MARK: - Derived

    private var uniqueStates: Int {
        Set(visited.compactMap { $0.state }).count
    }

    private var activeTripMiles: Double {
        guard let active = allTrips.first(where: { $0.completedAt == nil }) else { return 0 }
        return totalLegMiles(for: active.sortedStops)
    }

    private var totalTripMiles: Double {
        allTrips.reduce(0) { $0 + totalLegMiles(for: $1.sortedStops) }
    }

    private func totalLegMiles(for stops: [TripStop]) -> Double {
        guard stops.count >= 2 else { return 0 }
        var total: Double = 0
        for i in 1..<stops.count {
            guard let aLat = stops[i-1].lat, let aLng = stops[i-1].lng,
                  let bLat = stops[i].lat, let bLng = stops[i].lng else { continue }
            total += NearestNeighbor.haversine(lat1: aLat, lng1: aLng, lat2: bLat, lng2: bLng)
        }
        return total
    }

    private func formatMiles(_ m: Double) -> String {
        if m >= 1000 { return String(format: "%.1fk", m / 1000) }
        if m == 0 { return "—" }
        return "\(Int(m))"
    }
}

// MARK: - StatGridCard

private struct StatGridCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color
    var suffix: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(color.opacity(0.12)))
                    .overlay(Circle().strokeBorder(color.opacity(0.3), lineWidth: 1))
                Spacer()
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.frauncesNumeral(28))
                        .foregroundStyle(.fg)
                    if let suffix {
                        Text(suffix)
                            .font(.mono(11, weight: .medium))
                            .foregroundStyle(.muted)
                    }
                }
                Text(label.uppercased())
                    .font(.mono(10, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(.muted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.bark))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.line, lineWidth: 1))
    }
}
