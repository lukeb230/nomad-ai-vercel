//
//  StatStrip.swift
//  3-up stat cards: Visited / Trips / States.
//
//  Spec: redesign HTML lines 1473–1489 (`.stat-strip`).
//

import SwiftUI

struct StatStrip: View {
    let stats: MockStats
    var onTap: (StatKind) -> Void = { _ in }

    enum StatKind { case visited, trips, states }

    var body: some View {
        HStack(spacing: 10) {
            StatCard(
                value: stats.visited,
                label: "Visited",
                systemImage: "star",
                action: { onTap(.visited) }
            )
            StatCard(
                value: stats.trips,
                label: "Trips",
                systemImage: "checkmark.circle",
                action: { onTap(.trips) }
            )
            StatCard(
                value: stats.states,
                label: "States",
                systemImage: "house",
                action: { onTap(.states) }
            )
        }
    }
}

struct StatCard: View {
    let value: Int
    let label: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(value)")
                        .font(.frauncesNumeral(28))
                        .foregroundStyle(.fg)
                    Text(label.uppercased())
                        .font(.mono(11, weight: .medium))
                        .tracking(1.2)
                        .foregroundStyle(.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(.faint)
                    .padding(.top, 2).padding(.trailing, 2)
            }
            .padding(.horizontal, 12).padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.bark)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    StatStrip(stats: .sample)
        .padding()
        .background(Color.bg)
        .preferredColorScheme(.dark)
}
