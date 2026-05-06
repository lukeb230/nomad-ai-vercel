//
//  QuickActionGrid.swift
//  Magazine-style grid: 1 feature card spanning 2 cols + 2 small cards.
//
//  Spec: redesign HTML lines 1565–1589 (`.quick-grid`).
//

import SwiftUI

struct QuickActionGrid: View {
    var onTap: (Action) -> Void = { _ in }

    enum Action { case askAI, map, planRoute }

    var body: some View {
        VStack(spacing: 10) {
            // Feature card (full width)
            QuickCard(
                title: "Ask NomadAI where to go tonight",
                subtitle: "\u{201C}Quiet dispersed near me, no fee, flat pad\u{201D}",
                systemImage: "sparkle",
                isFeature: true,
                action: { onTap(.askAI) }
            )

            // Two small cards in a row
            HStack(spacing: 10) {
                QuickCard(
                    title: "What's near me",
                    subtitle: "Map mode",
                    systemImage: "map",
                    isFeature: false,
                    action: { onTap(.map) }
                )
                QuickCard(
                    title: "Plan a route",
                    subtitle: "8 saved ready",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    isFeature: false,
                    action: { onTap(.planRoute) }
                )
            }
        }
    }
}

private struct QuickCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isFeature: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                IconBlock(systemImage: systemImage)
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.frauncesCard(isFeature ? 18 : 17))
                        .foregroundStyle(.fg)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.body(12))
                        .foregroundStyle(.muted)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .padding(16)
            .aspectRatio(isFeature ? 2.6 : 1.15, contentMode: .fit)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        isFeature
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [Color.surface, Color.bark],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            : AnyShapeStyle(Color.bark)
                    )
            )
            .overlay(
                // Featured card has a clay glow in the bottom-right
                Group {
                    if isFeature {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                RadialGradient(
                                    colors: [Color.clay.opacity(0.2), .clear],
                                    center: UnitPoint(x: 1, y: 1),
                                    startRadius: 0,
                                    endRadius: 250
                                )
                            )
                            .allowsHitTesting(false)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct IconBlock: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 18, weight: .light))
            .foregroundStyle(.clay)
            .frame(width: 36, height: 36)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.surface2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.line, lineWidth: 1)
            )
    }
}

#Preview {
    QuickActionGrid()
        .padding(.horizontal, 16)
        .background(Color.bg)
        .preferredColorScheme(.dark)
}
