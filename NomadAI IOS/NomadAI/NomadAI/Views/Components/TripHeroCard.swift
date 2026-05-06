//
//  TripHeroCard.swift
//  The big hero card on Home — map preview + meta + stop-chip rail + progress.
//
//  Spec: redesign HTML lines 1426–1470 (`.trip-hero`).
//

import SwiftUI
import SwiftData
import MapKit

struct TripHeroCard: View {
    let trip: Trip

    @Environment(\.modelContext) private var modelContext
    @State private var routeCoords: [CLLocationCoordinate2D] = []

    // MARK: - Derived display

    private var stops: [TripStop] { trip.sortedStops }
    private var stopCount: Int { stops.count }

    private var stopCoords: [CLLocationCoordinate2D] {
        stops.compactMap(coord(for:))
    }

    /// Full sequence including user location (start / end) per the trip's flags.
    /// Used for the polyline + total-miles math + region-fitting.
    private var fullCoords: [CLLocationCoordinate2D] {
        let userLat = LocationService.shared.coordinateOrFallback.latitude
        let userLng = LocationService.shared.coordinateOrFallback.longitude
        return trip.routeCoordSequence(userLat: userLat, userLng: userLng)
    }

    private var title: String {
        guard stopCount >= 2,
              let first = stops.first?.campsiteName,
              let last = stops.last?.campsiteName
        else { return stops.first?.campsiteName ?? "Active trip" }
        return "\(first) → \(last)"
    }

    private var totalMilesString: String {
        let total = legDistances().reduce(0, +)
        if total == 0 { return "—" }
        return total >= 1000
            ? String(format: "%.1fk mi", total / 1000)
            : "\(Int(total)) mi"
    }

    private var stopCountString: String { "\(stopCount) stops" }

    private var progressPercent: Int {
        guard stopCount > 0 else { return 0 }
        return min(100, trip.currentStopIndex * 100 / stopCount)
    }

    private var dayOfTotal: String {
        "Day \(min(trip.currentStopIndex + 1, max(stopCount, 1))) of \(stopCount)"
    }

    var body: some View {
        VStack(spacing: 0) {
            mapPreview
            meta
        }
        .background(Color.bark)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.line, lineWidth: 1)
        )
        .shadowMd()
    }

    // MARK: - Map preview (180pt tall — real MapKit)

    private var mapPreview: some View {
        let region = Self.region(fitting: fullCoords.isEmpty ? stopCoords : fullCoords)

        return ZStack(alignment: .topLeading) {
            Map(initialPosition: .region(region), interactionModes: []) {
                MapPolyline(coordinates: routeCoords)
                    .stroke(Color.clay, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [4, 5]))
                ForEach(stops, id: \.persistentModelID) { stop in
                    if let coord = coord(for: stop) {
                        Annotation(stop.campsiteName, coordinate: coord) {
                            HeroStopDot(state: chipState(for: stop))
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic, emphasis: .muted))
            .environment(\.colorScheme, .dark)
            .task(id: routeTaskKey) {
                routeCoords = await RouteFetcher.driving(through: fullCoords)
            }

            LinearGradient(
                colors: [Color.bg.opacity(0.0), Color.bg.opacity(0.35)],
                startPoint: .top, endPoint: .bottom
            )
            .allowsHitTesting(false)

            HStack {
                Text("En Route")
                    .font(.mono(10, weight: .semibold))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(.clay)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.clay.opacity(0.15)))
                    .overlay(Capsule().strokeBorder(Color.clay.opacity(0.35), lineWidth: 1))
                    .background(.ultraThinMaterial, in: Capsule())
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text(dayOfTotal.uppercased())
                        .font(.mono(10, weight: .medium))
                        .tracking(1.2)
                        .foregroundStyle(.sage)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }
        }
        .frame(height: 180)
        .clipped()
        .overlay(
            Rectangle().fill(Color.line).frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Helpers

    private func coord(for stop: TripStop) -> CLLocationCoordinate2D? {
        guard let lat = stop.lat, let lng = stop.lng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    private func chipState(for stop: TripStop) -> MockStop.Status {
        let idx = stop.order
        let cur = trip.currentStopIndex
        if idx < cur { return .done }
        if idx == cur { return .next }
        return .future
    }

    private func legDistances() -> [Double] {
        let coords = fullCoords
        guard coords.count >= 2 else { return [] }
        var legs: [Double] = []
        for i in 1..<coords.count {
            legs.append(NearestNeighbor.haversine(
                lat1: coords[i-1].latitude, lng1: coords[i-1].longitude,
                lat2: coords[i].latitude, lng2: coords[i].longitude
            ))
        }
        return legs
    }

    /// Cache key for the polyline `.task`. Combines stop identity with the
    /// trip flags so toggling Round trip / Start from me triggers a refetch.
    private var routeTaskKey: [String] {
        var parts = stops.map { String(describing: $0.persistentModelID) }
        parts.append("round=\(trip.roundTrip)")
        parts.append("startFromMe=\(trip.startFromUserLocation)")
        return parts
    }

    /// Compute a region that fits the route comfortably, with padding.
    private static func region(fitting coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard let first = coords.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 38.5, longitude: -114),
                span: MKCoordinateSpan(latitudeDelta: 6, longitudeDelta: 12)
            )
        }
        var minLat = first.latitude, maxLat = first.latitude
        var minLng = first.longitude, maxLng = first.longitude
        for c in coords {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLng = min(minLng, c.longitude); maxLng = max(maxLng, c.longitude)
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max(0.05, (maxLat - minLat) * 1.4),
                longitudeDelta: max(0.05, (maxLng - minLng) * 1.4)
            )
        )
    }

    // MARK: - Meta (title + chip rail + progress)

    private var meta: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.frauncesTitle(22))
                    .foregroundStyle(.fg)
                    .kerning(-0.3)
                titleSub
            }

            stopsRail

            progressRow

            if let next = nextStop {
                nextStopRow(next)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    /// Stop the user is currently at the threshold of — the one whose
    /// `order` matches `trip.currentStopIndex`. nil when the trip is
    /// complete (cursor past last stop).
    private var nextStop: TripStop? {
        guard trip.currentStopIndex >= 0,
              trip.currentStopIndex < stops.count else { return nil }
        return stops[trip.currentStopIndex]
    }

    /// Row showing the next stop's name + a Mark visited CTA. Tapping advances
    /// the trip cursor, marks the matching Campsite as visited, and auto-
    /// completes the trip when past the final stop.
    private func nextStopRow(_ stop: TripStop) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("NEXT STOP")
                    .font(.mono(9, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(.muted)
                Text(stop.campsiteName)
                    .font(.frauncesCard(14))
                    .foregroundStyle(.fg)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { markNextVisited(stop) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Mark visited")
                        .font(.body(12, weight: .bold))
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .foregroundStyle(Color.clayInk)
                .background(Capsule().fill(Color.clay))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark \(stop.campsiteName) as visited")
        }
        .padding(.top, 4)
    }

    /// Same flow as MapView.markVisited — Campsite.isVisited flip,
    /// currentStopIndex bump, auto-completion + CompletedTrip on the
    /// final stop, and a notification reschedule.
    private func markNextVisited(_ stop: TripStop) {
        let now = Date()
        let campsiteId = stop.campsiteId
        var fetch = FetchDescriptor<Campsite>(predicate: #Predicate { $0.id == campsiteId })
        fetch.fetchLimit = 1
        if let campsite = try? modelContext.fetch(fetch).first {
            campsite.isVisited = true
            if campsite.visitedAt == nil { campsite.visitedAt = now }
            campsite.updatedAt = now
        }
        trip.currentStopIndex += 1
        trip.updatedAt = now
        if trip.currentStopIndex >= trip.sortedStops.count {
            trip.completedAt = now
            let completed = CompletedTrip(
                id: UUID(),
                completedAt: now,
                stopNames: trip.sortedStops.map(\.campsiteName),
                updatedAt: now
            )
            modelContext.insert(completed)
        }
        try? modelContext.save()
        Task { [modelContext] in
            let trips = (try? modelContext.fetch(FetchDescriptor<Trip>())) ?? []
            await NotificationService.shared.rebuildSchedule(from: trips)
        }
    }

    private var titleSub: some View {
        HStack(spacing: 8) {
            Text(totalMilesString)
            Text("·").foregroundStyle(.faint)
            Text(stopCountString)
        }
        .font(.body(12))
        .foregroundStyle(.muted)
        .lineLimit(1)
    }

    private var stopsRail: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(stops, id: \.persistentModelID) { stop in
                        StopChip(
                            n: stop.order + 1,
                            name: stop.campsiteName,
                            state: chipState(for: stop)
                        )
                        .id(stop.persistentModelID)
                    }
                }
            }
            // Land already-centered on the current stop (no animation on first
            // appear), then animate as the cursor advances on Mark visited.
            .onAppear { scrollToCurrent(proxy: proxy, animated: false) }
            .onChange(of: trip.currentStopIndex) { _, _ in
                scrollToCurrent(proxy: proxy, animated: true)
            }
            .onChange(of: stops.map(\.persistentModelID)) { _, _ in
                // If the underlying stops collection changes (reorder, add,
                // remove) re-anchor on whatever is current now.
                scrollToCurrent(proxy: proxy, animated: true)
            }
        }
    }

    /// Scroll the chip rail so the user's current stop sits centered in the
    /// visible area. Falls back to the last stop when the trip is complete.
    private func scrollToCurrent(proxy: ScrollViewProxy, animated: Bool) {
        let target = nextStop ?? stops.last
        guard let id = target?.persistentModelID else { return }
        let action = { proxy.scrollTo(id, anchor: .center) }
        if animated {
            withAnimation(.easeOut(duration: 0.4), action)
        } else {
            action()
        }
    }

    private var progressRow: some View {
        VStack(spacing: 10) {
            Rectangle().fill(Color.line)
                .frame(height: 1)
                .opacity(0.6)
                .overlay(
                    HStack(spacing: 4) {
                        ForEach(0..<60, id: \.self) { _ in
                            Rectangle()
                                .fill(Color.bark)
                                .frame(width: 4, height: 1)
                        }
                    }
                )
                .clipped()
                .padding(.horizontal, -2)

            HStack(spacing: 12) {
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.surface2).frame(height: 4)
                    GeometryReader { geo in
                        Capsule()
                            .fill(
                                LinearGradient(colors: [.moss, .clay],
                                               startPoint: .leading,
                                               endPoint: .trailing)
                            )
                            .frame(width: geo.size.width * CGFloat(progressPercent) / 100, height: 4)
                    }
                    .frame(height: 4)
                }
                Text("\(progressPercent)%")
                    .font(.mono(11, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(.muted)
                    .fixedSize()
            }
        }
    }
}

// MARK: - Stop chip (primitives — decoupled from MockStop)

struct StopChip: View {
    let n: Int
    let name: String
    let state: MockStop.Status

    private var bg: Color {
        switch state {
        case .next:    return Color.clay.opacity(0.1)
        case .done:    return Color.surface
        case .future:  return Color.surface
        }
    }
    private var border: Color {
        state == .next ? .clay : .line
    }
    private var label: Color {
        state == .done ? .muted : .fgDim
    }
    private var dotBg: Color {
        state == .done ? .moss : .clay
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("\(n)")
                .font(.mono(10, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(.clayInk)
                .frame(width: 18, height: 18)
                .background(Circle().fill(dotBg))

            Text(name)
                .font(.body(12, weight: .medium))
                .foregroundStyle(label)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.leading, 9)
        .padding(.trailing, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(bg))
        .overlay(Capsule().strokeBorder(border, lineWidth: 1))
    }
}

// MARK: - Hero stop dot (small annotation on the hero map)

private struct HeroStopDot: View {
    let state: MockStop.Status

    var body: some View {
        Circle()
            .fill(fill)
            .frame(width: state == .next ? 12 : 9, height: state == .next ? 12 : 9)
            .overlay(Circle().strokeBorder(Color.bg, lineWidth: state == .next ? 2 : 1.5))
            .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
    }

    private var fill: Color {
        switch state {
        case .done:   return .moss
        case .next:   return .clay
        case .future: return .slate
        }
    }
}
