//
//  JournalEntry.swift
//  Editorial journal entry row: 68px thumb + name + meta + stars + days-ago.
//
//  Spec: redesign HTML lines 1502–1554 (`.journal-entry`).
//

import SwiftUI

struct JournalList: View {
    let entries: [MockJournalEntry]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { idx, entry in
                JournalEntryRow(entry: entry, isLast: idx == entries.count - 1)
            }
        }
    }
}

struct JournalEntryRow: View {
    let entry: MockJournalEntry
    var isLast: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            JournalThumbnail(kind: entry.kind)
                .frame(width: 68, height: 68)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.frauncesCard(16))
                    .foregroundStyle(.fg)
                    .lineLimit(1)

                meta
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(entry.aside)
                .font(.mono(10, weight: .medium))
                .tracking(0.8)
                .foregroundStyle(.muted)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 6)
        .overlay(
            // dashed hairline divider, hidden on the last row
            Group {
                if !isLast {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 1)
                        .overlay(
                            DashedLine(dash: [2, 3])
                                .stroke(Color.line, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                        )
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        )
    }

    @ViewBuilder
    private var meta: some View {
        HStack(spacing: 6) {
            Text(entry.location)
                .font(.body(11))
                .foregroundStyle(.muted)
            Text("·").foregroundStyle(.faint)

            if let n = entry.stars {
                StarsRow(stars: n, total: 5)
            } else if let suffix = entry.metaSuffix {
                Text(suffix)
                    .font(.body(11))
                    .foregroundStyle(.muted)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Stars row (filled + empty SF Symbol)

private struct StarsRow: View {
    let stars: Int
    let total: Int

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<total, id: \.self) { i in
                Image(systemName: i < stars ? "star.fill" : "star")
                    .font(.system(size: 11))
                    .foregroundStyle(.clay)
            }
        }
    }
}

// MARK: - Thumbnail (no photo yet — abstract texture per kind)

struct JournalThumbnail: View {
    let kind: MockJournalEntry.Kind

    var body: some View {
        ZStack {
            background

            // Abstract horizon overlay
            Canvas { ctx, size in
                let w = size.width
                let h = size.height
                var path = Path()
                path.move(to: CGPoint(x: 0, y: h * 0.7))
                path.addCurve(
                    to: CGPoint(x: w, y: h * 0.65),
                    control1: CGPoint(x: w * 0.3, y: h * 0.55),
                    control2: CGPoint(x: w * 0.6, y: h * 0.78)
                )
                path.addLine(to: CGPoint(x: w, y: h))
                path.addLine(to: CGPoint(x: 0, y: h))
                path.closeSubpath()
                ctx.fill(path, with: .color(strokeTint.opacity(0.35)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.line, lineWidth: 1)
        )
    }

    private var background: some View {
        Group {
            switch kind {
            case .desert:
                LinearGradient(
                    colors: [Color(red: 0.785, green: 0.541, blue: 0.369),  // #c88a5e
                             Color(red: 0.416, green: 0.243, blue: 0.157)], // #6a3e28
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            case .sky:
                LinearGradient(
                    colors: [Color(red: 0.416, green: 0.533, blue: 0.565),  // #6a8890
                             Color(red: 0.165, green: 0.227, blue: 0.282)], // #2a3a48
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            case .canyon:
                LinearGradient(
                    colors: [Color(red: 0.785, green: 0.541, blue: 0.369),  // #c88a5e
                             Color(red: 0.416, green: 0.243, blue: 0.157)], // #6a3e28
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
        }
    }

    private var strokeTint: Color {
        switch kind {
        case .desert: return .moss
        case .sky:    return .fg
        case .canyon: return .fg
        }
    }
}

// MARK: - Helper for dashed line drawing

private struct DashedLine: Shape {
    let dash: [CGFloat]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

#Preview {
    JournalList(entries: MockJournalEntry.samples)
        .padding(.horizontal, 16)
        .background(Color.bg)
        .preferredColorScheme(.dark)
}
