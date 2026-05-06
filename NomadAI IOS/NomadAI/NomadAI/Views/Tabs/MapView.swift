//
//  MapView.swift
//  Tab 3 — MapKit-backed map with custom pins, route polyline, and floating mode bar.
//
//  Spec: docs/screen-inventory.md §3, redesign HTML lines 1739–1808.
//

import SwiftUI
import SwiftData
import MapKit

struct CampsiteMapView: View {
    enum MapMode: String, CaseIterable {
        case results, saved, route
        var label: String {
            switch self {
            case .results: return "Results"
            case .saved: return "Saved"
            case .route: return "Route"
            }
        }
        var systemImage: String {
            switch self {
            case .results: return "magnifyingglass"
            case .saved: return "bookmark"
            case .route: return "location.north"
            }
        }
    }

    @State private var nav = AppNavigationState.shared
    @State private var position: MapCameraPosition = .region(CampsiteMapView.region(for: AppNavigationState.shared.mapMode))

    @AppStorage("default_radius") private var searchRadius: Int = 50
    @Environment(\.modelContext) private var ctx
    @State private var store = SearchResultsStore.shared
    @Query(filter: #Predicate<Campsite> { $0.isSaved == true })
    private var savedCampsites: [Campsite]

    @State private var isSearchingArea: Bool = false
    @State private var detailCampsite: Campsite? = nil

    @Query(filter: #Predicate<Trip> { $0.completedAt == nil },
           sort: \Trip.startedAt, order: .reverse)
    private var activeTrips: [Trip]

    /// Trip we render in Route mode. ONLY the user-pinned active trip — no
    /// fallback. If the user has trips but hasn't pinned one, Route mode shows
    /// the empty card prompting them to pin one in Saved.
    private var activeTrip: Trip? {
        activeTrips.first(where: { $0.isActive })
    }
    private var routeStops: [TripStop] { activeTrip?.sortedStops ?? [] }

    /// Cache key for the polyline `.task`. Combines stop identity with the two
    /// flags so toggling Round trip / Start from me triggers a refetch.
    private var routeTaskKey: [String] {
        var parts = routeStops.map { String(describing: $0.persistentModelID) }
        parts.append("round=\(activeTrip?.roundTrip ?? false)")
        parts.append("startFromMe=\(activeTrip?.startFromUserLocation ?? false)")
        return parts
    }

    // Pan-to-search state
    @State private var lastSearchedCenter: CLLocationCoordinate2D? = nil
    @State private var currentCenter: CLLocationCoordinate2D? = nil
    @State private var showSearchAreaButton: Bool = false

    // Selected pin for popup
    @State private var selectedPin: Campsite? = nil
    @State private var selectedRouteStop: TripStop? = nil

    private let panThreshold: Double = 0.05  // degrees lat/lng

    /// Road-following polyline through the route stops. Populated by `.task`
    /// once MKDirections returns; empty until then.
    @State private var routeRoadCoords: [CLLocationCoordinate2D] = []

    var body: some View {
        @Bindable var nav = nav
        VStack(alignment: .leading, spacing: 12) {
            topbar
            mapCard
            routeInfoCard
            Spacer(minLength: 100)
        }
        .background(Color.bg)
        .onChange(of: nav.mapMode) { _, new in
            let region: MKCoordinateRegion
            if new == .route {
                let coords = routeStops.compactMap { mapCoord($0) }
                region = boundingRegion(for: coords) ?? Self.region(for: new)
            } else {
                region = Self.region(for: new)
            }
            withAnimation(.easeInOut(duration: 0.5)) {
                position = .region(region)
            }
            // Reset selection + pan-search state when switching modes.
            selectedPin = nil
            selectedRouteStop = nil
            showSearchAreaButton = false
            lastSearchedCenter = nil
        }
        .sheet(item: $detailCampsite) { campsite in
            CampsiteDetailSheet(campsite: campsite)
        }
        // NPS alerts only refresh from search-result regions — no device-
        // location refresh on tab open. Set when "Search this area" returns.
    }

    /// Region to fit the pins of each mode comfortably.
    private static func region(for mode: MapMode) -> MKCoordinateRegion {
        switch mode {
        case .results:
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 38.6, longitude: -109.55),
                span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.2)
            )
        case .saved:
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 38.0, longitude: -114.8),
                span: MKCoordinateSpan(latitudeDelta: 5.0, longitudeDelta: 5.0)
            )
        case .route:
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 38.4, longitude: -114.0),
                span: MKCoordinateSpan(latitudeDelta: 5.5, longitudeDelta: 13.0)
            )
        }
    }

    // MARK: - Topbar

    private var topbar: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Map").monoLabel()
                FrauncesEmphasis(prefix: "The ", italic: "field", suffix: "", size: 22)
            }
            NPSAlertsBanner()
        }
        .padding(.horizontal, Spacing.pageHorizontal)
        .padding(.top, 18)
    }

    // MARK: - Map card

    private var mapCard: some View {
        Map(position: $position) {
            mapContent
        }
        .mapStyle(.standard(elevation: .realistic))
        // Keep the map in dark mode regardless of app theme.
        .environment(\.colorScheme, .dark)
        .onMapCameraChange(frequency: .onEnd) { context in
            let center = context.region.center
            currentCenter = center
            if let last = lastSearchedCenter {
                let dLat = abs(center.latitude - last.latitude)
                let dLng = abs(center.longitude - last.longitude)
                if dLat > panThreshold || dLng > panThreshold {
                    showSearchAreaButton = true
                }
            }
            // First-time pan also triggers the button so users discover it.
            if lastSearchedCenter == nil { lastSearchedCenter = center }
        }
        .frame(height: 460)
        .overlay(alignment: .top) {
            @Bindable var nav = nav
            ModeBar(selected: $nav.mapMode)
        }
        .overlay(alignment: .top) {
            if showSearchAreaButton {
                SearchAreaButton(isLoading: isSearchingArea, action: searchThisArea)
                    .padding(.top, 70)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .center) {
            if let copy = emptyOverlayCopy, selectedPin == nil, selectedRouteStop == nil {
                EmptyMapCard(title: copy.title, subtitle: copy.subtitle)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if let pin = selectedPin {
                MapPopupCard(
                    title: pin.name,
                    meta: metaLine(for: pin),
                    sourceColor: pin.source.brandColor,
                    onClose: { selectedPin = nil },
                    onOpen: { detailCampsite = pin }
                ) {
                    SitePhotoView(campsite: pin, paged: false) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10).fill(Color.surface2)
                            Image(systemName: "photo")
                                .font(.system(size: 18, weight: .light))
                                .foregroundStyle(.muted)
                        }
                    }
                }
                .padding(12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let stop = selectedRouteStop {
                let matched = lookupCampsite(for: stop)
                let state = pinState(for: stop)
                MapPopupCard(
                    title: stop.campsiteName,
                    meta: "Stop \(stop.order + 1) of \(routeStops.count) · " + stopStateLabel(state),
                    sourceColor: routeStopColor(state),
                    onClose: { selectedRouteStop = nil },
                    onOpen: { if let c = matched { detailCampsite = c } }
                ) {
                    if let c = matched {
                        SitePhotoView(campsite: c, paged: false) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10).fill(Color.surface2)
                                Image(systemName: "photo")
                                    .font(.system(size: 18, weight: .light))
                                    .foregroundStyle(.muted)
                            }
                        }
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10).fill(Color.surface2)
                            Image(systemName: "photo")
                                .font(.system(size: 18, weight: .light))
                                .foregroundStyle(.muted)
                        }
                    }
                }
                .padding(12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.line, lineWidth: 1))
        .padding(.horizontal, Spacing.pageHorizontal)
        .animation(.easeOut(duration: 0.25), value: showSearchAreaButton)
        .animation(.easeOut(duration: 0.25), value: selectedPin)
        .animation(.easeOut(duration: 0.25), value: selectedRouteStop)
        .task(id: routeTaskKey) {
            // Fetch the road-following route whenever the stop set OR trip flags change.
            // The sequence may include user location at the start (startFromUserLocation)
            // and/or at the end (roundTrip) — the polyline reflects that automatically.
            let userLat = LocationService.shared.coordinateOrFallback.latitude
            let userLng = LocationService.shared.coordinateOrFallback.longitude
            let coords = activeTrip?.routeCoordSequence(userLat: userLat, userLng: userLng)
                ?? routeStops.compactMap { mapCoord($0) }
            routeRoadCoords = await RouteFetcher.driving(through: coords)
        }
    }

    @MapContentBuilder
    private var mapContent: some MapContent {
        switch nav.mapMode {
        case .results:
            ForEach(store.results) { site in
                if let coord = mapCoord(site) {
                    Annotation(site.name, coordinate: coord) {
                        PinView(color: site.source.brandColor, isActive: selectedPin?.id == site.id)
                            .onTapGesture {
                                selectedPin = site
                                selectedRouteStop = nil
                            }
                    }
                }
            }
        case .saved:
            ForEach(savedCampsites) { site in
                if let coord = mapCoord(site) {
                    Annotation(site.name, coordinate: coord) {
                        PinView(color: .clay, isActive: selectedPin?.id == site.id, filled: true)
                            .onTapGesture {
                                selectedPin = site
                                selectedRouteStop = nil
                            }
                    }
                }
            }
        case .route:
            // Dashed clay polyline that follows actual roads (fetched via MKDirections)
            MapPolyline(coordinates: routeRoadCoords)
                .stroke(
                    Color.clay,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [4, 6])
                )
            ForEach(routeStops, id: \.persistentModelID) { stop in
                if let coord = mapCoord(stop) {
                    Annotation(stop.campsiteName, coordinate: coord) {
                        RoutePinView(
                            number: stop.order + 1,
                            state: pinState(for: stop),
                            isActive: selectedRouteStop?.persistentModelID == stop.persistentModelID
                        )
                        .onTapGesture {
                            selectedRouteStop = stop
                            selectedPin = nil
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty-state overlay (centered card on the map)

    private var emptyOverlayCopy: (title: String, subtitle: String)? {
        switch nav.mapMode {
        case .results:
            guard store.results.isEmpty else { return nil }
            return ("No pins yet", "Search for campsites and the results will appear here.")
        case .saved:
            guard savedCampsites.isEmpty else { return nil }
            return ("No saved spots", "Bookmark a campsite from Search to see it here.")
        case .route:
            guard routeStops.isEmpty else { return nil }
            // Different copy depending on whether user has unpinned trips.
            if !activeTrips.isEmpty {
                let n = activeTrips.count
                return (
                    "No active trip set",
                    "You have \(n) trip\(n == 1 ? "" : "s") in Saved. Tap the star on one to pin it — it'll show up here."
                )
            }
            return ("No route yet", "Plan one in Saved → Route — pins appear when you add stops.")
        }
    }

    // MARK: - Route info card (below map)

    private var routeInfoCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(Color.clay)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.bark))
                .overlay(Circle().strokeBorder(Color.line, lineWidth: 1))

            VStack(alignment: .leading, spacing: 3) {
                Text(routeInfoTitle)
                    .font(.body(13, weight: .semibold))
                    .foregroundStyle(.fg)
                Text(routeInfoSubtitle)
                    .font(.body(11))
                    .foregroundStyle(.muted)
            }

            Spacer()

            if nav.mapMode == .results {
                Button(action: searchThisArea) {
                    HStack(spacing: 5) {
                        if isSearchingArea {
                            ProgressView().tint(Color.clayInk).controlSize(.small)
                        }
                        Text("Search area")
                            .font(.body(11, weight: .bold))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .foregroundStyle(Color.clayInk)
                    .background(Capsule().fill(Color.clay))
                }
                .buttonStyle(.plain)
                .disabled(isSearchingArea)
            } else if nav.mapMode == .route,
                      let trip = activeTrip,
                      trip.currentStopIndex < routeStops.count {
                let nextStop = routeStops[trip.currentStopIndex]
                Button(action: { markVisited(stop: nextStop, trip: trip) }) {
                    Text("Mark visited")
                        .font(.body(11, weight: .bold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .foregroundStyle(Color.clayInk)
                        .background(Capsule().fill(Color.clay))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.bark))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.line, lineWidth: 1))
        .padding(.horizontal, Spacing.pageHorizontal)
        .padding(.top, 4)
    }

    private var routeInfoTitle: String {
        switch nav.mapMode {
        case .results:
            return store.results.isEmpty ? "No results yet" : "Tap any pin to open"
        case .saved:
            return "Saved spots · \(savedCampsites.count)"
        case .route:
            guard let trip = activeTrip, !routeStops.isEmpty else { return "No active trip" }
            if trip.currentStopIndex >= routeStops.count { return "Trip complete" }
            let first = routeStops.first?.campsiteName ?? "Start"
            let last = routeStops.last?.campsiteName ?? "End"
            return routeStops.count >= 2 ? "\(first) → \(last)" : first
        }
    }

    private var routeInfoSubtitle: String {
        switch nav.mapMode {
        case .results:
            return store.results.isEmpty
                ? "Try Search, or pan the map and tap Search area."
                : "Pan the map to search a new area."
        case .saved:
            return savedCampsites.isEmpty
                ? "Bookmark a spot from Search to see it here."
                : "Tap a pin to open."
        case .route:
            guard let trip = activeTrip, !routeStops.isEmpty else {
                return "Plan one in Saved → Route."
            }
            if trip.currentStopIndex >= routeStops.count {
                return "All \(routeStops.count) stops visited."
            }
            return "\(routeStops.count) stops · Stop \(trip.currentStopIndex + 1) up next"
        }
    }

    // MARK: - Search this area

    private func searchThisArea() {
        guard let center = currentCenter, !isSearchingArea else { return }
        Task {
            isSearchingArea = true
            defer { isSearchingArea = false }
            do {
                let dtos = try await CampsiteService.shared.search(
                    lat: center.latitude,
                    lng: center.longitude,
                    radius: searchRadius,
                    limit: 30,
                    tags: [],
                    source: nil
                )
                let upserted = dtos.map { Campsite.upsert(from: $0, into: ctx) }
                try? ctx.save()
                store.results = upserted
                store.aiNote = AINote(
                    label: "\(upserted.count) found in this area",
                    tone: upserted.isEmpty ? .warning : .success
                )
                nav.mapMode = .results
                lastSearchedCenter = center
                showSearchAreaButton = false
                Task { await validateCoordinates(for: upserted, in: ctx) }
                if let state = dominantState(of: upserted) {
                    Task { await NPSAlertsService.shared.refreshForState(stateCode: state) }
                }
                // No fallback to map-center reverse-geocoding — the alerts
                // banner only ever reflects the region of cards in results.
            } catch {
                // Silent fail for now — Phase 9 polish for visible error UX.
            }
        }
    }

    // MARK: - Helpers

    /// Most-common state across results (for refreshing the NPS alerts banner
    /// so it reflects the area the user just searched, not device location).
    private func dominantState(of sites: [Campsite]) -> String? {
        let codes = sites.compactMap { $0.state?.uppercased() }.filter { $0.count == 2 }
        guard !codes.isEmpty else { return nil }
        return Dictionary(grouping: codes, by: { $0 })
            .mapValues(\.count)
            .max(by: { $0.value < $1.value })?
            .key
    }

    /// Build the popup meta line from a real Campsite — fee + city/state.
    private func metaLine(for site: Campsite) -> String {
        var parts: [String] = []
        if let fee = site.fee, !fee.isEmpty { parts.append(fee) }
        let loc = [site.city, site.state].compactMap { $0 }.joined(separator: ", ")
        if !loc.isEmpty { parts.append(loc) }
        return parts.joined(separator: " · ")
    }

    /// CLLocationCoordinate2D from a Campsite, or nil if either coord is missing.
    private func mapCoord(_ site: Campsite) -> CLLocationCoordinate2D? {
        guard let lat = site.lat, let lng = site.lng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    private func mapCoord(_ stop: TripStop) -> CLLocationCoordinate2D? {
        guard let lat = stop.lat, let lng = stop.lng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    /// Derive done/next/future from Trip.currentStopIndex.
    private func pinState(for stop: TripStop) -> MockStop.Status {
        let cur = activeTrip?.currentStopIndex ?? 0
        if stop.order < cur { return .done }
        if stop.order == cur { return .next }
        return .future
    }

    /// Look up the matching Campsite for a TripStop by id.
    private func lookupCampsite(for stop: TripStop) -> Campsite? {
        let id = stop.campsiteId
        var fetch = FetchDescriptor<Campsite>(predicate: #Predicate { $0.id == id })
        fetch.fetchLimit = 1
        return try? ctx.fetch(fetch).first
    }

    /// Compute the bounding box of a coordinate set with 40% padding.
    private func boundingRegion(for coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard !coords.isEmpty else { return nil }
        let lats = coords.map(\.latitude)
        let lngs = coords.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lngs.min()! + lngs.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.5, (lats.max()! - lats.min()!) * 1.4),
            longitudeDelta: max(0.5, (lngs.max()! - lngs.min()!) * 1.4)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    // MARK: - Trip lifecycle

    private func markVisited(stop: TripStop, trip: Trip) {
        let now = Date()
        // 1. Mark the matching Campsite as visited (so it appears in Passport).
        if let campsite = lookupCampsite(for: stop) {
            campsite.isVisited = true
            if campsite.visitedAt == nil { campsite.visitedAt = now }
            campsite.updatedAt = now
        }
        // 2. Advance the trip's cursor.
        trip.currentStopIndex += 1
        trip.updatedAt = now
        // 3. Auto-complete when past the last stop.
        if trip.currentStopIndex >= trip.sortedStops.count {
            trip.completedAt = now
            let completed = CompletedTrip(
                id: UUID(),
                completedAt: now,
                stopNames: trip.sortedStops.map(\.campsiteName),
                updatedAt: now
            )
            ctx.insert(completed)
        }
        try? ctx.save()
        // Cancel/refresh notifications now that this stop's order < currentStopIndex.
        Task {
            let trips = (try? ctx.fetch(FetchDescriptor<Trip>())) ?? []
            await NotificationService.shared.rebuildSchedule(from: trips)
        }
        // Clear popup if it was showing the stop we just marked.
        if selectedRouteStop?.persistentModelID == stop.persistentModelID {
            selectedRouteStop = nil
        }
    }

    private func routeStopColor(_ state: MockStop.Status) -> Color {
        switch state {
        case .done:   return .moss
        case .next:   return .clay
        case .future: return .slate
        }
    }

    private func stopStateLabel(_ state: MockStop.Status) -> String {
        switch state {
        case .done:   return "Visited"
        case .next:   return "Tonight"
        case .future: return "Upcoming"
        }
    }
}

// MARK: - Empty-state card (centered on the map when no pins to show)

private struct EmptyMapCard: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "map")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.muted)
            Text(title)
                .font(.body(15, weight: .bold))
                .foregroundStyle(.fg)
            Text(subtitle)
                .font(.body(12))
                .foregroundStyle(.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 22).padding(.vertical, 20)
        .frame(maxWidth: 280)
        .background(.ultraThinMaterial.opacity(0.8))
        .background(Color.bark.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 4)
    }
}

// MARK: - Mode bar (3-segment toggle, glass-blur)

private struct ModeBar: View {
    @Binding var selected: CampsiteMapView.MapMode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(CampsiteMapView.MapMode.allCases, id: \.self) { m in
                Button { selected = m } label: {
                    HStack(spacing: 5) {
                        Image(systemName: m.systemImage).font(.system(size: 11, weight: .regular))
                        Text(m.label).font(.body(11, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .foregroundStyle(selected == m ? Color.clayInk : Color.fgDim)
                    .background(RoundedRectangle(cornerRadius: 10).fill(selected == m ? Color.clay : Color.clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(.ultraThinMaterial.opacity(0.8))
        .background(Color.bark.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.line, lineWidth: 1))
        .padding(12)
    }
}

// MARK: - Custom pin (teardrop + dot)

private struct PinView: View {
    let color: Color
    let isActive: Bool
    var filled: Bool = false

    var body: some View {
        ZStack {
            Image(systemName: filled ? "mappin.circle.fill" : "mappin.circle")
                .font(.system(size: isActive ? 32 : 26, weight: .regular))
                .foregroundStyle(color)
                .background(
                    Circle()
                        .fill(Color.bark)
                        .frame(width: isActive ? 30 : 24, height: isActive ? 30 : 24)
                )
                .shadow(color: .black.opacity(0.4), radius: 3, y: 2)

            // Center dot for the teardrop look
            Circle()
                .fill(Color.bark)
                .frame(width: 6, height: 6)
        }
        .scaleEffect(isActive ? 1.0 : 0.92)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
    }
}

// MARK: - Numbered route stop pin

private struct RoutePinView: View {
    let number: Int
    let state: MockStop.Status
    let isActive: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: isActive ? 30 : 26, height: isActive ? 30 : 26)
                .overlay(Circle().strokeBorder(Color.bg, lineWidth: 2))
                .shadow(color: .black.opacity(0.4), radius: 3, y: 2)

            Text("\(number)")
                .font(.body(12, weight: .bold))
                .foregroundStyle(state == .next ? Color.clayInk : Color.bg)
        }
        .scaleEffect(isActive ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
    }

    private var color: Color {
        switch state {
        case .done:   return .moss
        case .next:   return .clay
        case .future: return .slate
        }
    }
}

// MARK: - Search-this-area button (appears after pan)

private struct SearchAreaButton: View {
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView().tint(Color.clayInk).controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold))
                }
                Text("Search this area").font(.body(12, weight: .bold))
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .foregroundStyle(Color.clayInk)
            .background(Capsule().fill(Color.clay))
            .shadow(color: Color.clay.opacity(0.35), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

// MARK: - Map popup card (bottom sheet)

private struct MapPopupCard<Thumb: View>: View {
    let title: String
    let meta: String
    let sourceColor: Color
    let onClose: () -> Void
    let onOpen: () -> Void
    @ViewBuilder let thumb: () -> Thumb

    var body: some View {
        HStack(spacing: 12) {
            thumb()
                .frame(width: 52, height: 52)
                .overlay(alignment: .bottomLeading) {
                    Rectangle().fill(sourceColor).frame(width: 12, height: 3).padding(4)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.frauncesCard(15))
                    .foregroundStyle(.fg)
                    .lineLimit(1)
                Text(meta)
                    .font(.body(11))
                    .foregroundStyle(.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: onOpen) {
                Text("Open")
                    .font(.body(11, weight: .bold))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .foregroundStyle(Color.clayInk)
                    .background(Capsule().fill(Color.clay))
            }
            .buttonStyle(.plain)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.muted)
                    .padding(8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.bark))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.line, lineWidth: 1))
        .shadowMd()
    }
}

#Preview {
    CampsiteMapView().preferredColorScheme(.dark)
}
