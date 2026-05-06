//
//  StampTile.swift
//  Passport stamp tile — collectible square with circle/rect variants,
//  6 color rotations, rotated date cancel, and locked state.
//
//  Spec: redesign HTML lines 1254–1338 (`.stamp` + variants).
//

import SwiftUI

struct StampTile: View {
    let name: String
    let location: String   // "NV · Free"
    let serial: String     // "024"
    let date: String?      // "Apr 12" — nil for locked
    let icon: String       // SF Symbol name
    let color: Color       // .moss / .clay / .rust / .slate / .sand / .berry
    let variant: Variant
    let isLocked: Bool

    enum Variant { case circle, rect }

    var body: some View {
        ZStack {
            background

            // Inner dashed border
            innerBorder

            // Diagonal stripe overlay for locked
            if isLocked {
                stripePattern.allowsHitTesting(false)
            }

            // Content
            VStack(alignment: .leading, spacing: 0) {
                topRow
                Spacer(minLength: 0)
                bottomBlock
            }
            .padding(14)

            // Date cancel — bottom-right, rotated
            if let date {
                Text(date.uppercased())
                    .font(.mono(9, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(.muted)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.bark))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.line, lineWidth: 1))
                    .rotationEffect(.degrees(-6))
                    .padding(.trailing, 14).padding(.bottom, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .opacity(isLocked ? 0 : 1)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(Color.line, lineWidth: 1))
        .shadowSm()
        .opacity(isLocked ? 0.5 : 1.0)
    }

    @ViewBuilder
    private var background: some View {
        switch variant {
        case .rect:
            Color.bark
        case .circle:
            ZStack {
                Color.bark
                Circle()
                    .fill(Color.surface)
                    .padding(8)
            }
        }
    }

    @ViewBuilder
    private var innerBorder: some View {
        let stroke = StrokeStyle(lineWidth: 1.5, dash: [3, 3])
        switch variant {
        case .rect:
            RoundedRectangle(cornerRadius: 12)
                .inset(by: 8)
                .strokeBorder(color.opacity(isLocked ? 0.15 : 0.25), style: stroke)
        case .circle:
            Circle()
                .inset(by: 14)
                .strokeBorder(color.opacity(isLocked ? 0.15 : 0.25), style: stroke)
        }
    }

    private var stripePattern: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let spacing: CGFloat = 9
                let stripeWidth: CGFloat = 1
                ctx.translateBy(x: size.width / 2, y: size.height / 2)
                ctx.rotate(by: .degrees(45))
                ctx.translateBy(x: -size.width, y: -size.height)
                let total = size.width * 2
                var x: CGFloat = 0
                while x < total {
                    let rect = CGRect(x: x, y: 0, width: stripeWidth, height: size.height * 2)
                    ctx.fill(Path(rect), with: .color(Color.surface))
                    x += spacing
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .opacity(0.5)
    }

    // MARK: - Content sub-views

    private var topRow: some View {
        HStack(alignment: .top) {
            ZStack {
                Circle()
                    .fill(Color.surface2)
                    .frame(width: 38, height: 38)
                    .overlay(Circle().strokeBorder(color.opacity(isLocked ? 0.4 : 1), lineWidth: 1.5))
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(isLocked ? Color.faint : color)
            }
            Spacer()
            Text(serial)
                .font(.mono(10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(isLocked ? .faint : .muted)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.bark.opacity(0.7)))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.line, lineWidth: 1))
        }
    }

    private var bottomBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.frauncesCard(13))
                .foregroundStyle(isLocked ? Color.faint : Color.fg)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(location.uppercased())
                .font(.mono(10, weight: .medium))
                .tracking(1.0)
                .foregroundStyle(isLocked ? .faint : .muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
        StampTile(name: "Hickison Pet.", location: "NV · Free", serial: "001", date: "Apr 12", icon: "leaf",         color: .moss,  variant: .rect,   isLocked: false)
        StampTile(name: "Ward Mountain",  location: "NV · Free", serial: "002", date: "Apr 02", icon: "mountain.2",   color: .clay,  variant: .circle, isLocked: false)
        StampTile(name: "Bonneville",     location: "UT",        serial: "003", date: "Mar 19", icon: "sun.max",      color: .rust,  variant: .rect,   isLocked: false)
        StampTile(name: "Locked",         location: "—",         serial: "—",   date: nil,      icon: "lock",         color: .slate, variant: .rect,   isLocked: true)
    }
    .padding()
    .background(Color.bg)
    .preferredColorScheme(.dark)
}
