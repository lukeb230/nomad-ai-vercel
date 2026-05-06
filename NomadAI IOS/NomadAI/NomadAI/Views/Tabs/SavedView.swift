//
//  SavedView.swift
//  Tab 4 — Timeline route planner + Passport.
//
//  Spec: docs/screen-inventory.md §4, redesign HTML lines 1811–1931.
//

import SwiftUI
import SwiftData
import CoreLocation

struct SavedView: View {
    enum Mode: String, CaseIterable {
        case route, all, passport
        var label: String {
            switch self {
            case .route:    return "Route"
            case .all:      return "All saved"
            case .passport: return "Passport"
            }
        }
    }

    enum AllSort: String, CaseIterable {
        case date, alpha, distance
        var label: String {
            switch self {
            case .date:     return "Date"
            case .alpha:    return "A–Z"
            case .distance: return "Distance"
            }
        }
    }

    @Environment(\.modelContext) private var ctx

    @Query(filter: #Predicate<Trip> { $0.completedAt == nil },
           sort: \Trip.startedAt, order: .reverse)
    private var activeTrips: [Trip]

    /// Currently-displayed trip in Route mode. Defaults to the most-recently-
    /// updated active trip (`activeTrips.first`); swapped via the chip picker
    /// at the top of the route panel.
    @State private var selectedTripId: UUID? = nil

    @Query(filter: #Predicate<Campsite> { $0.isSaved == true })
    private var saved: [Campsite]

    @Query(filter: #Predicate<Campsite> { $0.isVisited == true },
           sort: [SortDescriptor(\.visitedAt, order: .reverse)])
    private var visited: [Campsite]

    @Query private var completed: [CompletedTrip]

    @State private var mode: Mode = .route
    @State private var sort: AllSort = .date
    @State private var stateFilter: String = "All"
    @State private var stopForDateSheet: TripStop? = nil
    @State private var shareURL: ShareableURL? = nil
    @State private var sharingError: String? = nil

    // Confirmation flows for destructive actions.
    @State private var stopToDelete: TripStop? = nil
    @State private var showingDeleteRouteConfirm: Bool = false

    // Fluid drag-to-reorder state.
    @State private var draggedStopId: String? = nil
    @State private var dragOffset: CGFloat = 0          // dragged row's finger tracking
    @State private var dragTargetIdx: Int? = nil        // slot the dragged row is currently aiming for; only changes at threshold crossings
    private let dragRowStride: CGFloat = 86  // TimelineStopRow + LegLabel center-to-center

    private var userLat: Double { LocationService.shared.coordinateOrFallback.latitude }
    private var userLng: Double { LocationService.shared.coordinateOrFallback.longitude }

    /// Trip currently being viewed in Route mode. Picker selection wins; if
    /// nothing is picked, fall through to the user-pinned active trip; if
    /// none, the most-recently-started active trip.
    private var selectedTrip: Trip? {
        if let id = selectedTripId,
           let match = activeTrips.first(where: { $0.id == id }) {
            return match
        }
        return activeTrips.first(where: { $0.isActive }) ?? activeTrips.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                topbar
                hero
                NPSAlertsBanner()
                    .padding(.horizontal, Spacing.pageHorizontal)

                ModeTabs(mode: $mode)
                    .padding(.horizontal, Spacing.pageHorizontal)

                Group {
                    switch mode {
                    case .route:    routePanel
                    case .all:      allPanel
                    case .passport: passportPanel
                    }
                }
                .padding(.horizontal, Spacing.pageHorizontal)

                Spacer(minLength: 100)
            }
        }
        .background(Color.bg)
        .sheet(item: $stopForDateSheet) { stop in
            if let trip = selectedTrip {
                StopDateSheet(stop: stop, trip: trip)
            }
        }
        .sheet(item: $shareURL) { share in
            ShareSheetView(url: share.url, summary: tripSummary(selectedTrip))
        }
        .alert("Couldn't share trip", isPresented: Binding(
            get: { sharingError != nil },
            set: { if !$0 { sharingError = nil } }
        )) {
            Button("OK") { sharingError = nil }
        } message: {
            Text(sharingError ?? "")
        }
        .alert(
            "Remove this stop?",
            isPresented: Binding(
                get: { stopToDelete != nil },
                set: { if !$0 { stopToDelete = nil } }
            ),
            presenting: stopToDelete
        ) { stop in
            Button("Remove", role: .destructive) { deleteStop(stop) }
            Button("Cancel", role: .cancel) { stopToDelete = nil }
        } message: { stop in
            Text("\(stop.campsiteName) will be removed from this route.")
        }
        .alert(
            "Delete this route?",
            isPresented: $showingDeleteRouteConfirm
        ) {
            Button("Delete", role: .destructive) { deleteRoute() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("All stops will be removed and this trip will be deleted. This can't be undone.")
        }
        // NPS alerts only refresh based on search-result regions (set by
        // SearchView/MapView when new results land). No device-location
        // refresh on tab open — banner persists from the most recent search.
    }

    // MARK: - Topbar / Hero

    private var topbar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Saved").monoLabel()
            FrauncesEmphasis(prefix: "Your ", italic: "pins", suffix: "", size: 22)
        }
        .padding(.horizontal, Spacing.pageHorizontal)
        .padding(.top, 18)
    }

    private var hero: some View {
        FrauncesEmphasis(
            prefix: activeTrips.isEmpty ? "No " : "The ",
            italic: activeTrips.isEmpty ? "active trip" : (activeTrips.count > 1 ? "long ways" : "long way"),
            suffix: activeTrips.isEmpty ? " — start one." : " — your drafts",
            size: 28
        )
        .foregroundStyle(.fg)
        .padding(.horizontal, Spacing.pageHorizontal)
    }

    // MARK: - Route panel

    @ViewBuilder
    private var routePanel: some View {
        if let trip = selectedTrip {
            VStack(spacing: 12) {
                // Selected trip — fully expanded with timeline + actions.
                expandedTripCard(trip: trip)

                // Other active trips render as compact cards. Tap to swap which
                // one is expanded above. Active (user-pinned) trip shows a star.
                let others = activeTrips.filter { $0.persistentModelID != trip.persistentModelID }
                if !others.isEmpty {
                    VStack(spacing: 8) {
                        Text("OTHER TRIPS")
                            .font(.mono(9, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 6)
                        ForEach(others, id: \.persistentModelID) { other in
                            collapsedTripCard(trip: other)
                        }
                    }
                }
            }
        } else {
            emptyCard(
                icon: "map",
                title: "No active trip",
                body: "Save spots from Search and tap Add to route to start planning a route."
            )
        }
    }

    /// The selected trip's full timeline + controls. Same content as before;
    /// just split out so the routePanel layout reads cleanly with the
    /// collapsed cards below.
    private func expandedTripCard(trip: Trip) -> some View {
        VStack(spacing: 14) {
            timelineHeader(trip: trip)
            tripMetaStrip(trip: trip)
            timelineList(trip: trip)
            actionRow(trip: trip)
        }
    }

    /// Compact one-row card for non-selected active trips. Tap to swap which
    /// trip is expanded above.
    private func collapsedTripCard(trip: Trip) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.25)) {
                selectedTripId = trip.id
            }
        } label: {
            HStack(spacing: 10) {
                if trip.isActive {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.clay)
                }
                Text(trip.displayName)
                    .font(.frauncesCard(15))
                    .foregroundStyle(.fg)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(trip.stops.count) STOP\(trip.stops.count == 1 ? "" : "S")")
                    .font(.mono(10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(.muted)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.muted)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.bark))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Switch to \(trip.displayName), \(trip.stops.count) stops\(trip.isActive ? ", active trip" : "")")
    }

    private func timelineHeader(trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TimelineToggle(label: "Round trip", systemImage: "arrow.triangle.2.circlepath", isOn: trip.roundTrip) {
                    trip.roundTrip.toggle()
                    trip.updatedAt = Date()
                    try? ctx.save()
                }
                TimelineToggle(label: "Start from me", systemImage: "location", isOn: trip.startFromUserLocation) {
                    trip.startFromUserLocation.toggle()
                    trip.updatedAt = Date()
                    try? ctx.save()
                }
                Spacer()
                TimelineToggle(label: "Optimize", systemImage: "sparkles", isPrimary: true) {
                    optimize(trip: trip)
                }
            }
            // Pin / unpin as the user's active trip — drives Home hero + Map
            // Route default. Only one trip can be active at a time.
            TimelineToggle(
                label: trip.isActive ? "Active trip" : "Set as active",
                systemImage: trip.isActive ? "star.fill" : "star",
                isOn: trip.isActive
            ) {
                if trip.isActive {
                    Trip.clearActive(trip, in: ctx)
                } else {
                    Trip.setActive(trip, in: ctx)
                }
            }
        }
    }

    private func tripMetaStrip(trip: Trip) -> some View {
        let stops = trip.sortedStops
        let totalMi = totalMiles(trip: trip)
        let stopCount = stops.count
        let drivingHours = totalMi / 55.0
        let totalFee = sumFees(stops: stops)

        return HStack(spacing: 0) {
            MetricCell(value: formattedMiles(totalMi), unit: "mi", label: "Total")
            metricSep
            MetricCell(value: "\(stopCount)", unit: nil, label: "Stops")
            metricSep
            MetricCell(value: String(format: "%.1f", drivingHours), unit: "hr", label: "Driving")
            metricSep
            MetricCell(value: totalFee == 0 ? "Free" : "$\(totalFee)", unit: nil, label: "Fees")
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.bark))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.line, lineWidth: 1))
    }

    private var metricSep: some View {
        Rectangle().fill(Color.line).frame(width: 1, height: 28).padding(.horizontal, 4)
    }

    private func timelineList(trip: Trip) -> some View {
        let stops = trip.sortedStops
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(stops.enumerated()), id: \.element.persistentModelID) { index, stop in
                if index > 0 {
                    LegLabel(
                        miles: legMiles(prev: stops[index - 1], next: stop)
                    )
                }
                TimelineStopRow(
                    stop: stop,
                    index: index,
                    total: stops.count,
                    isDragging: stop.campsiteId == draggedStopId,
                    onHandleChanged: { translation in
                        handleDragChanged(stopId: stop.campsiteId, translation: translation, allStops: stops)
                    },
                    onHandleEnded: { translation in
                        commitDragReorder(trip: trip, stopId: stop.campsiteId, translation: translation)
                    },
                    onTap: { stopForDateSheet = stop },
                    onDelete: { stopToDelete = stop }
                )
                .offset(y: rowYOffset(originalIndex: index, allStops: stops))
                .zIndex(stop.campsiteId == draggedStopId ? 10 : 0)
            }
            if trip.roundTrip, !stops.isEmpty {
                RoundTripLegLabel(
                    miles: roundTripLegMiles(trip: trip),
                    backToUserLocation: trip.startFromUserLocation
                )
            }
        }
        .padding(.leading, 22)  // room for the spine + dot
        .background(alignment: .leading) {
            DashedSpine().frame(width: 2).padding(.leading, 11).padding(.top, 14).padding(.bottom, 30)
        }
    }

    /// Distance from the last stop back to the route's start (user location or first stop).
    private func roundTripLegMiles(trip: Trip) -> Double {
        let coords = trip.routeCoordSequence(userLat: userLat, userLng: userLng)
        guard coords.count >= 2 else { return 0 }
        let prev = coords[coords.count - 2]
        let last = coords[coords.count - 1]
        return NearestNeighbor.haversine(
            lat1: prev.latitude, lng1: prev.longitude,
            lat2: last.latitude, lng2: last.longitude
        )
    }

    // MARK: - Fluid drag reorder

    /// Visual y-offset for each row while a drag is in progress.
    /// - The dragged row tracks the finger directly via `dragOffset` (no animation).
    /// - Rows between the dragged item's original slot and `dragTargetIdx` shift
    ///   one stride up or down. `dragTargetIdx` only changes at threshold crossings,
    ///   inside `withAnimation`, so unaffected rows never see a spurious offset.
    private func rowYOffset(originalIndex idx: Int, allStops: [TripStop]) -> CGFloat {
        guard let dragged = draggedStopId,
              let draggedIdx = allStops.firstIndex(where: { $0.campsiteId == dragged })
        else { return 0 }
        if idx == draggedIdx { return dragOffset }
        guard let target = dragTargetIdx else { return 0 }
        if target > draggedIdx, idx > draggedIdx, idx <= target { return -dragRowStride }
        if target < draggedIdx, idx >= target, idx < draggedIdx { return dragRowStride }
        return 0
    }

    private func handleDragChanged(stopId: String, translation: CGFloat, allStops: [TripStop]) {
        // First frame of a new drag.
        if draggedStopId != stopId {
            draggedStopId = stopId
            dragTargetIdx = allStops.firstIndex(where: { $0.campsiteId == stopId })
        }
        dragOffset = translation

        // Update target slot only at threshold crossings, animated.
        if let draggedIdx = allStops.firstIndex(where: { $0.campsiteId == stopId }) {
            let crossed = Int(round(translation / dragRowStride))
            let newTarget = max(0, min(allStops.count - 1, draggedIdx + crossed))
            if newTarget != dragTargetIdx {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    dragTargetIdx = newTarget
                }
            }
        }
    }

    private func commitDragReorder(trip: Trip, stopId: String, translation: CGFloat) {
        let stops = trip.sortedStops
        guard let sourceIdx = stops.firstIndex(where: { $0.campsiteId == stopId }) else {
            draggedStopId = nil
            dragOffset = 0
            dragTargetIdx = nil
            return
        }
        let crossed = Int(round(translation / dragRowStride))
        let target = max(0, min(stops.count - 1, sourceIdx + crossed))
        // Slot-aligned final offset: where the dragged row should end up visually
        // before the SwiftData reorder snaps it to its new array index.
        let finalOffset = CGFloat(target - sourceIdx) * dragRowStride

        // Spring the dragged row to its target slot. Other rows' offsets stay
        // constant during this animation because they depend on `dragTargetIdx`,
        // not `dragOffset`.
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            dragOffset = finalOffset
        } completion: {
            // Same render frame: SwiftData reorder + state clear. The dragged row's
            // new array slot lines up exactly with where the spring left it visually,
            // and the displacement-compensation cancels out for the swapped neighbors,
            // so there's no visible jump anywhere.
            if target != sourceIdx {
                let currentStops = trip.sortedStops
                if let srcIdx = currentStops.firstIndex(where: { $0.campsiteId == stopId }) {
                    var arr = currentStops
                    let pick = arr.remove(at: srcIdx)
                    arr.insert(pick, at: target)
                    for (i, s) in arr.enumerated() { s.order = i }
                    trip.updatedAt = Date()
                    try? ctx.save()
                }
            }
            draggedStopId = nil
            dragOffset = 0
            dragTargetIdx = nil
        }
    }

    private func actionRow(trip: Trip) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ActionPill(label: "Map view", systemImage: "map") {
                    AppNavigationState.shared.openMap(mode: .route)
                }
                ActionPill(label: "Share route", systemImage: "square.and.arrow.up") {
                    Task {
                        do {
                            let url = try await ShareService.shared.createShareLink(for: trip)
                            await MainActor.run { shareURL = ShareableURL(url: url) }
                        } catch {
                            await MainActor.run { sharingError = error.localizedDescription }
                        }
                    }
                }
            }
            ActionPill(label: "Start trip", systemImage: "play.fill", isPrimary: true) {
                trip.currentStopIndex = 0
                trip.updatedAt = Date()
                try? ctx.save()
                AppNavigationState.shared.selectedTab = .home
            }
            Button {
                showingDeleteRouteConfirm = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash").font(.system(size: 11))
                    Text("Delete route").font(.body(11, weight: .semibold))
                }
                .foregroundStyle(Color.berry)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            Text("Long-press a stop to remove it.")
                .font(.body(11))
                .foregroundStyle(.muted)
                .frame(maxWidth: .infinity)
        }
        .padding(.top, 10)
    }

    // MARK: - Destructive helpers

    private func deleteStop(_ stop: TripStop) {
        defer { stopToDelete = nil }
        guard let trip = selectedTrip else { return }
        var stops = trip.sortedStops
        guard let removeIdx = stops.firstIndex(where: { $0.persistentModelID == stop.persistentModelID })
        else { return }

        // If this is the last stop, deleting it leaves an empty trip — kill the
        // trip itself so the empty-state card can take over.
        let lastStop = stops.count <= 1

        let removed = stops.remove(at: removeIdx)
        ctx.delete(removed)
        for (i, s) in stops.enumerated() { s.order = i }

        // Keep currentStopIndex valid relative to the new stop count.
        if trip.currentStopIndex > removeIdx { trip.currentStopIndex -= 1 }
        trip.currentStopIndex = max(0, min(trip.currentStopIndex, stops.count))
        trip.updatedAt = Date()

        if lastStop {
            ctx.delete(trip)
        }
        try? ctx.save()
    }

    private func deleteRoute() {
        guard let trip = selectedTrip else { return }
        let deletedId = trip.id
        for stop in trip.stops {
            ctx.delete(stop)
        }
        ctx.delete(trip)
        try? ctx.save()
        // If we just deleted the selected trip, fall back to the next one (or
        // nil if the list is empty).
        if selectedTripId == deletedId {
            selectedTripId = nil
        }
    }

    // MARK: - All panel

    @ViewBuilder
    private var allPanel: some View {
        let filtered = filteredSorted()
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(eyebrow: "Bookmarks", title: "All saved · \(saved.count)")
                .padding(.top, 4)

            HStack(spacing: 8) {
                Menu {
                    Button("All") { stateFilter = "All" }
                    ForEach(availableStates, id: \.self) { s in
                        Button(s) { stateFilter = s }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "line.3.horizontal.decrease").font(.system(size: 11))
                        Text("State · \(stateFilter)").font(.body(12, weight: .semibold))
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .foregroundStyle(.fgDim)
                    .background(Capsule().fill(Color.bark))
                    .overlay(Capsule().strokeBorder(Color.line, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Spacer()

                ForEach(AllSort.allCases, id: \.self) { s in
                    SortChip(label: s.label, isOn: sort == s) { sort = s }
                }
            }

            if filtered.isEmpty {
                emptyCard(
                    icon: "bookmark",
                    title: saved.isEmpty ? "No saved spots yet" : "No saved spots in \(stateFilter)",
                    body: saved.isEmpty ? "Bookmark spots from Search to see them here." : "Pick a different state filter."
                )
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(filtered) { CampsiteCard(campsite: $0) }
                }
            }
        }
    }

    private var availableStates: [String] {
        Array(Set(saved.compactMap { $0.state }).sorted())
    }

    private func filteredSorted() -> [Campsite] {
        let filtered = saved.filter {
            stateFilter == "All" || $0.state == stateFilter
        }
        switch sort {
        case .date:
            return filtered.sorted { ($0.savedAt ?? .distantPast) > ($1.savedAt ?? .distantPast) }
        case .alpha:
            return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .distance:
            return filtered.sorted {
                let d0 = NearestNeighbor.haversine(lat1: userLat, lng1: userLng, lat2: $0.lat ?? 0, lng2: $0.lng ?? 0)
                let d1 = NearestNeighbor.haversine(lat1: userLat, lng1: userLng, lat2: $1.lat ?? 0, lng2: $1.lng ?? 0)
                return d0 < d1
            }
        }
    }

    // MARK: - Passport panel

    private var passportPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            passportCover
            StatStrip(stats: MockStats(
                visited: visited.count,
                trips: completed.count,
                states: uniqueStateCount
            ))
            .padding(.top, 4)

            if visited.isEmpty {
                Text("Stamps fill in as you mark stops visited.")
                    .font(.body(12))
                    .foregroundStyle(.muted)
                    .padding(.top, 4)
            }

            stampGrid
        }
    }

    private var passportCover: some View {
        let parchment = Color(red: 0.91, green: 0.86, blue: 0.75)
        return VStack(alignment: .leading, spacing: 6) {
            Text("NomadAI · Field Passport")
                .font(.mono(10, weight: .semibold))
                .tracking(2.0).textCase(.uppercase)
                .foregroundStyle(parchment.opacity(0.6))
            Text("Book No. 01")
                .font(.frauncesNumeral(30))
                .foregroundStyle(parchment)
            Text("\(visited.count) stamps · \(uniqueStateCount) states · \(completed.count) trips")
                .font(.body(12))
                .foregroundStyle(parchment.opacity(0.8))
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(red: 0.35, green: 0.24, blue: 0.16),
                         Color(red: 0.43, green: 0.29, blue: 0.18)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .inset(by: 6)
                .strokeBorder(parchment.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadowMd()
    }

    private var stampGrid: some View {
        let stampColors: [Color] = [.moss, .clay, .rust, .slate, .sand, .berry]
        let stampIcons = ["leaf", "mountain.2", "sun.max", "tent", "drop", "binoculars"]
        let totalSlots = max(visited.count + 3, 8)

        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(0..<totalSlots, id: \.self) { i in
                if i < visited.count {
                    let v = visited[i]
                    StampTile(
                        name: v.name,
                        location: [v.state, v.fee ?? "—"].compactMap { $0 }.joined(separator: " · "),
                        serial: String(format: "%03d", i + 1),
                        date: shortDate(v.visitedAt),
                        icon: stampIcons[i % stampIcons.count],
                        color: stampColors[abs(v.id.hashValue) % stampColors.count],
                        variant: i % 3 == 1 ? .circle : .rect,
                        isLocked: false
                    )
                } else {
                    StampTile(
                        name: "Locked",
                        location: "—",
                        serial: String(format: "%03d", i + 1),
                        date: nil,
                        icon: "lock",
                        color: .slate,
                        variant: i % 3 == 1 ? .circle : .rect,
                        isLocked: true
                    )
                }
            }
        }
    }

    private var uniqueStateCount: Int {
        Set(visited.compactMap { $0.state }).count
    }

    // MARK: - Helpers — drag/reorder

    private func moveStop(trip: Trip, sourceCampsiteId: String, toIndex: Int) {
        var stops = trip.sortedStops
        guard let sourceIdx = stops.firstIndex(where: { $0.campsiteId == sourceCampsiteId }) else { return }
        var targetIndex = toIndex
        if targetIndex > sourceIdx { targetIndex -= 1 }
        targetIndex = max(0, min(targetIndex, stops.count - 1))
        guard targetIndex != sourceIdx else { return }
        let pick = stops.remove(at: sourceIdx)
        stops.insert(pick, at: targetIndex)
        for (i, s) in stops.enumerated() { s.order = i }
        trip.updatedAt = Date()
        try? ctx.save()
    }

    private func optimize(trip: Trip) {
        let optimized = NearestNeighbor.order(
            stops: trip.sortedStops,
            startFromUserLocation: trip.startFromUserLocation,
            roundTrip: trip.roundTrip,
            userLat: userLat, userLng: userLng
        )
        for (i, s) in optimized.enumerated() { s.order = i }
        trip.updatedAt = Date()
        try? ctx.save()
    }

    // MARK: - Helpers — math/format

    private func totalMiles(trip: Trip) -> Double {
        let coords = trip.routeCoordSequence(userLat: userLat, userLng: userLng)
        guard coords.count >= 2 else { return 0 }
        var total: Double = 0
        for i in 1..<coords.count {
            total += NearestNeighbor.haversine(
                lat1: coords[i-1].latitude, lng1: coords[i-1].longitude,
                lat2: coords[i].latitude,   lng2: coords[i].longitude
            )
        }
        return total
    }

    private func legMiles(prev: TripStop, next: TripStop) -> Double {
        guard let pLat = prev.lat, let pLng = prev.lng,
              let nLat = next.lat, let nLng = next.lng else { return 0 }
        return NearestNeighbor.haversine(lat1: pLat, lng1: pLng, lat2: nLat, lng2: nLng)
    }

    private func sumFees(stops: [TripStop]) -> Int {
        // Stops link to Campsites by id. We may not have all linked Campsites
        // in the seed (route stops have placeholder ids), so fall back to 0.
        // TODO: when stops point to real Campsites, parse $XX/night → Int.
        return 0
    }

    private func formattedMiles(_ m: Double) -> String {
        if m >= 1000 {
            return String(format: "%.1fk", m / 1000)
        }
        return "\(Int(m))"
    }

    private func shortDate(_ d: Date?) -> String? {
        guard let d else { return nil }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: d)
    }

    // MARK: - Empty card helper

    private func emptyCard(icon: String, title: String, body: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 32, weight: .light)).foregroundStyle(.muted)
            Text(title).font(.body(14, weight: .semibold)).foregroundStyle(.muted)
            Text(body).font(.body(12)).foregroundStyle(.faint).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(40)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.bark))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.line, lineWidth: 1))
    }
}

// MARK: - ModeTabs (underline pill style)

private struct ModeTabs: View {
    @Binding var mode: SavedView.Mode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SavedView.Mode.allCases, id: \.self) { m in
                Button { mode = m } label: {
                    Text(m.label)
                        .font(.body(12, weight: .semibold))
                        .foregroundStyle(mode == m ? Color.fg : Color.muted)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(mode == m ? Color.clay : Color.clear)
                                .frame(height: 2)
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }
}

// MARK: - TimelineToggle (header pills)

private struct TimelineToggle: View {
    let label: String
    let systemImage: String
    var isOn: Bool = false
    var isPrimary: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage).font(.system(size: 10, weight: .regular))
                Text(label).font(.body(11, weight: .semibold))
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .foregroundStyle(fg)
            .background(Capsule().fill(bg))
            .overlay(Capsule().strokeBorder(border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var fg: Color {
        if isPrimary { return Color.clayInk }
        return isOn ? Color.bg : Color.fgDim
    }
    private var bg: Color {
        if isPrimary { return Color.clay }
        return isOn ? Color.moss : Color.bark
    }
    private var border: Color {
        if isPrimary { return Color.clay }
        return isOn ? Color.moss : Color.line
    }
}

// MARK: - MetricCell (Fraunces numeral + mono label)

private struct MetricCell: View {
    let value: String
    let unit: String?
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value).font(.frauncesNumeral(18)).foregroundStyle(.fg)
                if let unit {
                    Text(unit).font(.mono(10, weight: .medium)).foregroundStyle(.muted)
                }
            }
            Text(label.uppercased())
                .font(.mono(10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - DashedSpine (vertical dotted line behind the timeline)

private struct DashedSpine: View {
    var body: some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: CGPoint(x: 1, y: 0))
                p.addLine(to: CGPoint(x: 1, y: geo.size.height))
            }
            .stroke(Color.line, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 4]))
        }
    }
}

// MARK: - LegLabel (compass + miles between stops)

private struct LegLabel: View {
    let miles: Double

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color.line).frame(width: 14, height: 1)
            Image(systemName: "location.north").font(.system(size: 9))
            Text(milesString)
                .font(.mono(10, weight: .medium))
                .tracking(0.8)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.muted)
        .padding(.vertical, 6)
    }

    private var milesString: String {
        if miles >= 1 {
            return "\(Int(miles)) mi"
        }
        return "—"
    }
}

// MARK: - RoundTripLegLabel (closes the loop after the last stop)

private struct RoundTripLegLabel: View {
    let miles: Double
    let backToUserLocation: Bool

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color.clay.opacity(0.5)).frame(width: 14, height: 1)
            Image(systemName: "arrow.uturn.left").font(.system(size: 9))
            Text(label)
                .font(.mono(10, weight: .semibold))
                .tracking(0.8)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.clay)
        .padding(.vertical, 8)
    }

    private var label: String {
        let mi = miles >= 1 ? "\(Int(miles)) mi · " : ""
        return "\(mi)BACK TO \(backToUserLocation ? "MY LOCATION" : "START")"
    }
}

// MARK: - TimelineStopRow

private struct TimelineStopRow: View {
    let stop: TripStop
    let index: Int
    let total: Int
    let isDragging: Bool
    var onHandleChanged: (CGFloat) -> Void = { _ in }
    var onHandleEnded: (CGFloat) -> Void = { _ in }
    var onTap: () -> Void = {}
    var onDelete: () -> Void = {}

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Numbered dot
            ZStack {
                Circle()
                    .fill(dotBg)
                    .frame(width: 22, height: 22)
                    .overlay(Circle().strokeBorder(dotBorder, lineWidth: 2))
                Text("\(stop.order + 1)")
                    .font(.mono(10, weight: .bold))
                    .foregroundStyle(dotFg)
            }
            .padding(.leading, -22)  // pull onto the spine

            // Card
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.surface2)
                    .frame(width: 38, height: 38)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 14, weight: .light))
                            .foregroundStyle(.muted)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(stop.campsiteName)
                        .font(.frauncesCard(14))
                        .foregroundStyle(.fg)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text(stopBadgeLabel)
                            .font(.mono(9, weight: .semibold))
                            .tracking(1.0)
                            .foregroundStyle(.muted)
                        datePill
                    }
                }

                Spacer()

                // Drag handle — DragGesture(minimumDistance: 0) means the row
                // starts following the finger the instant the handle is touched.
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isDragging ? Color.clay : .muted)
                    .padding(8)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Drag to reorder")
                    .gesture(
                        // .global coordinate space — without this, the row's own
                        // .offset modifier moves the gesture's local origin, which
                        // causes translation.height to oscillate as the row catches
                        // up to the finger.
                        DragGesture(minimumDistance: 0, coordinateSpace: .global)
                            .onChanged { v in onHandleChanged(v.translation.height) }
                            .onEnded   { v in onHandleEnded(v.translation.height) }
                    )
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.bark))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(isDragging ? Color.clay : Color.line, lineWidth: 1))
            .shadow(color: .black.opacity(isDragging ? 0.3 : 0), radius: isDragging ? 14 : 0, y: isDragging ? 6 : 0)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .contextMenu {
                Button(role: .destructive, action: onDelete) {
                    Label("Remove from route", systemImage: "trash")
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var scheduledLabel: String {
        guard let d = stop.scheduledDate else { return "+ DATE" }
        let cal = Calendar.current
        let f = DateFormatter()
        if cal.isDateInToday(d) {
            f.dateFormat = "'TODAY ·' h:mm a"
        } else if cal.isDateInTomorrow(d) {
            f.dateFormat = "'TMRW ·' h:mm a"
        } else {
            f.dateFormat = "EEE M/d · h:mm a"
        }
        return f.string(from: d).uppercased()
    }

    @ViewBuilder
    private var datePill: some View {
        let scheduled = stop.scheduledDate != nil
        let fg: Color = scheduled ? .clay : .muted
        let bg: Color = scheduled ? Color.clay.opacity(0.12) : Color.clear
        let border: Color = scheduled ? Color.clay.opacity(0.3) : Color.line.opacity(0.4)
        Text(scheduledLabel)
            .font(.mono(9, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(fg)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(bg))
            .overlay(Capsule().strokeBorder(border, lineWidth: 1))
    }

    private var isStart: Bool { index == 0 }
    private var isEnd: Bool { index == total - 1 }

    private var dotBg: Color {
        if isStart { return Color.clay }
        if isEnd { return Color.moss }
        return Color.bg
    }
    private var dotBorder: Color {
        if isStart { return Color.clay }
        if isEnd { return Color.moss }
        return Color.clay
    }
    private var dotFg: Color {
        if isStart || isEnd { return Color.clayInk }
        return Color.clay
    }
    private var stopBadgeLabel: String {
        if isStart { return "START" }
        if isEnd { return "END" }
        return "STOP \(index + 1) OF \(total)"
    }
}

// MARK: - ActionPill (Map view / Share / Start trip)

private struct ActionPill: View {
    let label: String
    let systemImage: String
    var isPrimary: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.system(size: 11, weight: .regular))
                Text(label).font(.body(12, weight: .semibold))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 11)
            .foregroundStyle(isPrimary ? Color.clayInk : Color.fgDim)
            .background(RoundedRectangle(cornerRadius: 12).fill(isPrimary ? Color.clay : Color.bark))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isPrimary ? Color.clay : Color.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SortChip

private struct SortChip: View {
    let label: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.body(11, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .foregroundStyle(isOn ? Color.clayInk : Color.fgDim)
                .background(Capsule().fill(isOn ? Color.clay : Color.bark))
                .overlay(Capsule().strokeBorder(isOn ? Color.clay : Color.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Share helpers

private struct ShareableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct ShareSheetView: View {
    let url: URL
    let summary: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Share route").monoLabel()
                FrauncesEmphasis(prefix: "Send your ", italic: "trip", suffix: ".", size: 22)
                    .foregroundStyle(.fg)
                Text(summary)
                    .font(.body(13)).foregroundStyle(.muted)
            }

            Text(url.absoluteString)
                .font(.mono(11))
                .foregroundStyle(.fgDim)
                .lineLimit(2)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.surface))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.line, lineWidth: 1))

            ShareLink(
                item: url,
                subject: Text("Check out my trip"),
                message: Text(summary)
            ) {
                Text("Share via…")
                    .font(.body(14, weight: .bold))
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .foregroundStyle(Color.clayInk)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.clay))
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.pageHorizontal)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bg)
        .presentationDetents([.medium])
    }
}

private func tripSummary(_ trip: Trip?) -> String {
    guard let trip = trip else { return "" }
    let stops = trip.sortedStops
    let names = stops.map(\.campsiteName)
    let title: String
    if names.count >= 2 {
        title = "\(names.first!) → \(names.last!)"
    } else {
        title = names.first ?? "My trip"
    }
    return "\(title) · \(stops.count) stops"
}

#Preview {
    SavedView()
        .preferredColorScheme(.dark)
        .modelContainer(for: [Trip.self, TripStop.self, Campsite.self, CompletedTrip.self, Profile.self], inMemory: true)
}
