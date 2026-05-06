//
//  CampsiteCard.swift
//  Components — the most-reused atom in the app.
//
//  Spec: docs/screen-inventory.md (§Cross-cutting components),
//        redesign HTML lines 720–940 for `.site-card`.
//

import SwiftUI

struct CampsiteCard: View {
    let campsite: Campsite
    @State private var expanded: Bool = false

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
                if expanded {
                    expandedSection.padding(.top, 12)
                }
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
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color.bark)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(Color.line, lineWidth: 1))
        .shadowSm()
    }

    // MARK: - Photo (placeholder)

    private var photo: some View {
        Rectangle()
            .fill(Color.surface2)
            .aspectRatio(16/9, contentMode: .fit)
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.muted)
            )
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
            // Data cells 2x2
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 1) {
                DataCell(systemImage: "thermometer", label: "Weather", value: "—")
                DataCell(systemImage: "wind", label: "Wind", value: "—")
                DataCell(systemImage: "sun.horizon", label: "Sunrise", value: "—")
                DataCell(systemImage: "moon", label: "Sunset", value: "—")
            }
            .background(Color.line)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.line, lineWidth: 1))

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
                ActionButton(label: "Directions", system: "location.north", style: .primary, action: {})
                ActionButton(label: "Source", system: "globe", style: .outline, action: {})
                ActionButton(label: "Saved", system: "bookmark", style: campsite.isSaved ? .toggledSaved : .outline, action: {})
                ActionButton(label: "Trip", system: "plus", style: .outline, action: {})
            }
            .padding(.top, 4)
        }
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
