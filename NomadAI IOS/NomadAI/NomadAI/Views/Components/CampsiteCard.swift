//
//  CampsiteCard.swift
//  Components — the most-reused atom in the app.
//
//  Spec: docs/screen-inventory.md (§Cross-cutting components),
//        redesign HTML lines 720–940 for `.site-card`.
//

import SwiftUI
import SwiftData
import UIKit
import MapKit

struct CampsiteCard: View {
    let campsite: Campsite
    let initiallyExpanded: Bool
    @State private var expanded: Bool
    @State private var weatherSnapshot: WeatherCache.Snapshot? = nil
    @State private var routeBuilder = RouteBuilderState.shared
    @Environment(\.modelContext) private var modelContext

    init(campsite: Campsite, initiallyExpanded: Bool = false) {
        self.campsite = campsite
        self.initiallyExpanded = initiallyExpanded
        self._expanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(spacing: 0) {
            photo
            VStack(alignment: .leading, spacing: 0) {
                header
                fieldPills
                if let desc = campsite.siteDescription {
                    Text(desc)
                        .font(.body(13))
                        .foregroundStyle(.fgDim)
                        .lineSpacing(2)
                        .padding(.top, 10)
                }
                // While the route builder is open, expose Add to route at the
                // top level so the user doesn't have to expand each card to
                // pick stops. The button inside the expanded action row stays
                // in place too — both reflect the same toggle state.
                if routeBuilder.isActive {
                    inlineRouteButton
                        .padding(.top, 10)
                }
                if expanded {
                    expandedSection.padding(.top, 12)
                }
                if !initiallyExpanded {
                    Button {
                        withAnimation(.easeOut(duration: 0.25)) { expanded.toggle() }
                    } label: {
                        HStack {
                            Text(expanded ? "Hide field data" : "Show field data")
                                .font(.mono(10, weight: .semibold)).tracking(1.4).textCase(.uppercase)
                            Image(systemName: "chevron.down")
                                .rotationEffect(.degrees(expanded ? 180 : 0))
                                .font(.system(size: 10))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .foregroundStyle(.muted)
                        .overlay(alignment: .top) {
                            Rectangle().fill(Color.line)
                                .frame(height: 1)
                                .opacity(0.5)
                                .overlay(
                                    Rectangle().fill(.clear)
                                        .border(.clear, width: 1)
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color.bark)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(Color.line, lineWidth: 1))
        .shadowSm()
        .onChange(of: expanded) { _, isExpanded in
            if isExpanded, weatherSnapshot == nil,
               let lat = campsite.lat, let lng = campsite.lng {
                Task {
                    weatherSnapshot = await WeatherCache.shared.snapshot(
                        for: campsite.id, lat: lat, lng: lng
                    )
                }
            }
        }
        .task {
            // If the card is initially expanded (used by CampsiteDetailSheet), kick off
            // the fetch immediately rather than waiting for an onChange that won't fire.
            if expanded, weatherSnapshot == nil,
               let lat = campsite.lat, let lng = campsite.lng {
                weatherSnapshot = await WeatherCache.shared.snapshot(
                    for: campsite.id, lat: lat, lng: lng
                )
            }
        }
    }

    // MARK: - Helpers

    private func formatShortTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: d)
    }

    private func openAppleWeather() {
        guard let lat = campsite.lat, let lng = campsite.lng else { return }
        if let url = URL(string: "https://weather.apple.com/?location=\(lat),\(lng)") {
            UIApplication.shared.open(url)
        }
    }

    /// True iff we have coordinates that survive a sanity check. Drives the
    /// Directions button's visibility — no point rendering a button that's
    /// going to drop the user at a random pin.
    private var canDirect: Bool {
        guard let lat = campsite.lat, let lng = campsite.lng else { return false }
        if lat == 0 && lng == 0 { return false }
        if abs(lat) > 90 || abs(lng) > 180 { return false }
        return true
    }

    private func openDirections() {
        guard let lat = campsite.lat, let lng = campsite.lng, canDirect else { return }
        // MKMapItem is the Apple-recommended path: shows the campsite name
        // as the destination label (not raw lat/lng), respects the user's
        // current location as the origin without us having to pass it, and
        // honors driving-mode explicitly.
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coord))
        item.name = campsite.name
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

    private func openSource() {
        // Resolver guarantees a non-nil URL — it falls back to a Google
        // search of source + name + state when nothing better resolves, so
        // the button is never a dead tap.
        UIApplication.shared.open(SourceURLResolver.resolve(for: campsite))
    }

    private func toggleSaved() {
        campsite.isSaved.toggle()
        if campsite.isSaved {
            campsite.savedAt = Date()
        }
        campsite.updatedAt = Date()
        try? modelContext.save()
    }

    private func addToTrip() {
        // Prefer the user-pinned active trip when present; fall back to the
        // most-recently-updated active trip; create a new one if none exist.
        let trip: Trip
        let activeFetch = FetchDescriptor<Trip>(
            predicate: #Predicate { $0.completedAt == nil && $0.isActive == true }
        )
        if let pinned = try? modelContext.fetch(activeFetch).first {
            trip = pinned
        } else {
            var fallback = FetchDescriptor<Trip>(
                predicate: #Predicate { $0.completedAt == nil },
                sortBy: [
                    SortDescriptor(\.updatedAt, order: .reverse),
                    SortDescriptor(\.startedAt, order: .reverse),
                ]
            )
            fallback.fetchLimit = 1
            if let existing = try? modelContext.fetch(fallback).first {
                trip = existing
            } else {
                trip = Trip(id: UUID(), startedAt: Date())
                modelContext.insert(trip)
            }
        }

        if trip.stops.contains(where: { $0.campsiteId == campsite.id }) {
            return
        }

        let nextOrder = (trip.stops.map(\.order).max() ?? -1) + 1
        let stop = TripStop(
            order: nextOrder,
            campsiteId: campsite.id,
            campsiteName: campsite.name,
            lat: campsite.lat,
            lng: campsite.lng
        )
        stop.trip = trip
        modelContext.insert(stop)
        trip.updatedAt = Date()
        try? modelContext.save()
    }

    // MARK: - Photo (placeholder)

    private var photo: some View {
        SitePhotoView(campsite: campsite) {
            Rectangle()
                .fill(Color.surface2)
                .overlay(
                    Image(systemName: "photo")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.muted)
                )
        }
        .aspectRatio(16/9, contentMode: .fill)
        .clipped()
        .overlay(alignment: .topLeading) { sourceBadge }
        .overlay(alignment: .topTrailing) { feeBadge }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: Radius.lg, topTrailingRadius: Radius.lg))
    }

    private var sourceBadge: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(campsite.source.brandColor).frame(width: 7, height: 7)
            Text(campsite.sourceLabel.uppercased())
                .font(.mono(10, weight: .semibold)).tracking(1.2)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .foregroundStyle(.white)
        .background(.ultraThinMaterial.opacity(0.8))
        .background(Color.black.opacity(0.55))
        .clipShape(Capsule())
        .padding(12)
    }

    private var feeBadge: some View {
        Text(campsite.fee ?? "Free")
            .font(.mono(11, weight: .bold)).tracking(0.5)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(campsite.fee?.contains("$") == true ? Color.sand : Color.sage)
            .background(Color.black.opacity(0.7))
            .clipShape(Capsule())
            .padding(12)
    }

    // MARK: - Body sections

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(campsite.name).cardName().foregroundStyle(.fg).lineLimit(2)
                if campsite.city != nil || campsite.state != nil {
                    HStack(spacing: 5) {
                        Image(systemName: "location").font(.system(size: 10))
                        Text([campsite.city, campsite.state].compactMap { $0 }.joined(separator: ", "))
                            .font(.body(12))
                    }
                    .foregroundStyle(.sky)
                }
            }
            Spacer()
            // Distance placeholder
            Text("—")
                .font(.mono(11, weight: .semibold)).tracking(0.5)
                .foregroundStyle(.muted)
        }
    }

    private var fieldPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if !campsite.reservable {
                    FieldPill(text: "Walk-up", systemImage: "person.walking")
                } else {
                    FieldPill(text: "Reservable", systemImage: "calendar")
                }
                if campsite.fee == "Free" || campsite.fee == nil {
                    FieldPill(text: "No fee", systemImage: "dollarsign.circle")
                }
                ForEach(campsite.tags.prefix(3), id: \.self) { tag in
                    FieldPill(text: tag.capitalized, systemImage: nil)
                }
            }
        }
        .padding(.top, 10)
    }

    private var expandedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Data cells 2x2 — values flow in from WeatherCache once the user expands.
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 1) {
                DataCell(
                    systemImage: weatherSnapshot?.conditionSymbol ?? "thermometer",
                    label: "Weather",
                    value: weatherSnapshot.map { "\(Int($0.temperatureF.rounded()))°" } ?? "—"
                )
                DataCell(
                    systemImage: "wind",
                    label: "Wind",
                    value: weatherSnapshot.map { "\(Int($0.windSpeedMph.rounded())) \($0.windDirection)" } ?? "—"
                )
                DataCell(
                    systemImage: "sun.horizon",
                    label: "Sunrise",
                    value: weatherSnapshot?.sunrise.map(formatShortTime) ?? "—"
                )
                DataCell(
                    systemImage: "moon",
                    label: "Sunset",
                    value: weatherSnapshot?.sunset.map(formatShortTime) ?? "—"
                )
            }
            .background(Color.line)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.line, lineWidth: 1))

            // Apple WeatherKit attribution (legal requirement). Tap → opens Apple Weather.
            if weatherSnapshot != nil {
                Button(action: openAppleWeather) {
                    HStack(spacing: 4) {
                        Image(systemName: "apple.logo").font(.system(size: 9))
                        Text("Weather data from \u{F8FF} Weather")
                            .font(.mono(9, weight: .medium)).tracking(0.4)
                        Image(systemName: "arrow.up.right").font(.system(size: 8))
                    }
                    .foregroundStyle(.muted)
                }
                .buttonStyle(.plain)
            }

            // Tag chips
            if !campsite.tags.isEmpty {
                FlowLayout(spacing: 5) {
                    ForEach(campsite.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.mono(10, weight: .medium)).tracking(0.6)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .foregroundStyle(.muted)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.surface))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.lineSoft, lineWidth: 1))
                    }
                }
            }

            // Action row
            HStack(spacing: 6) {
                if canDirect {
                    ActionButton(label: "Directions", system: "location.north", style: .primary, action: openDirections)
                }
                ActionButton(label: "Source", system: "globe", style: .outline, action: openSource)
                ActionButton(label: campsite.isSaved ? "Saved" : "Save", system: "bookmark", style: campsite.isSaved ? .toggledSaved : .outline, action: toggleSaved)
                tripOrRouteButton
            }
            .padding(.top, 4)
        }
    }

    /// In normal mode this is the existing "Trip" button (adds to active Trip).
    /// While the route builder is open, it morphs into a toggle that adds /
    /// removes the campsite from the in-progress route selection.
    @ViewBuilder
    private var tripOrRouteButton: some View {
        if routeBuilder.isActive {
            let added = routeBuilder.contains(campsite.id)
            ActionButton(
                label: added ? "Added" : "Add to route",
                system: added ? "checkmark" : "plus",
                style: added ? .toggledSaved : .outline,
                action: { routeBuilder.toggle(campsite.id) }
            )
        } else {
            ActionButton(label: "Trip", system: "plus", style: .outline, action: addToTrip)
        }
    }

    /// Full-width Add to route toggle shown above the "Show field data" expander
    /// when the route builder is active, so users can pick stops without
    /// expanding each card.
    private var inlineRouteButton: some View {
        let added = routeBuilder.contains(campsite.id)
        return Button {
            routeBuilder.toggle(campsite.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: added ? "checkmark" : "plus")
                    .font(.system(size: 11, weight: .semibold))
                Text(added ? "Added to route" : "Add to route")
                    .font(.body(12, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(added ? Color.clayInk : Color.clay)
            .background(Capsule().fill(added ? Color.clay : Color.clay.opacity(0.12)))
            .overlay(Capsule().strokeBorder(Color.clay.opacity(added ? 0 : 0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(added ? "Remove from route" : "Add to route")
    }
}

// MARK: - Sub-components

struct FieldPill: View {
    let text: String
    var systemImage: String?
    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 10)) }
            Text(text).font(.body(11, weight: .medium))
        }
        .padding(.horizontal, 9).padding(.vertical, 3)
        .foregroundStyle(.fgDim)
        .background(RoundedRectangle(cornerRadius: 999).fill(Color.surface))
        .overlay(RoundedRectangle(cornerRadius: 999).strokeBorder(Color.line, lineWidth: 1))
    }
}

struct DataCell: View {
    let systemImage: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .light))
                .foregroundStyle(.clay)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.bark))
                .overlay(Circle().strokeBorder(Color.line, lineWidth: 1))

            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.mono(9, weight: .semibold)).tracking(1.0).textCase(.uppercase).foregroundStyle(.muted)
                Text(value).font(.body(12, weight: .semibold)).foregroundStyle(.fg)
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.surface)
    }
}

struct ActionButton: View {
    enum Style { case primary, outline, destructive, toggledSaved }
    let label: String
    let system: String
    let style: Style
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: system).font(.system(size: 11, weight: .regular))
                Text(label).font(.body(11, weight: .semibold))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 9)
            .foregroundStyle(fg)
            .background(RoundedRectangle(cornerRadius: 10).fill(bg))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var fg: Color {
        switch style {
        case .primary: return .clayInk
        case .outline: return .fgDim
        case .destructive: return .berry
        case .toggledSaved: return .clay
        }
    }
    private var bg: Color {
        switch style {
        case .primary: return .clay
        default: return .surface
        }
    }
    private var border: Color {
        switch style {
        case .primary: return .clay
        case .toggledSaved: return .clay
        case .destructive: return .berry.opacity(0.5)
        case .outline: return .line
        }
    }
}

// MARK: - Simple FlowLayout (for tag chips)

/// A minimal flow layout — wraps subviews onto multiple lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var w: CGFloat = 0, h: CGFloat = 0, lineH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if w + s.width > maxW { h += lineH + spacing; w = 0; lineH = 0 }
            w += s.width + spacing
            lineH = max(lineH, s.height)
        }
        return CGSize(width: maxW.isFinite ? maxW : w, height: h + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxW = bounds.width
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX { y += lineH + spacing; x = bounds.minX; lineH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
    }
}
