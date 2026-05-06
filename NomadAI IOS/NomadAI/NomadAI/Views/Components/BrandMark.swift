//
//  BrandMark.swift
//  The "NomadAI" brand mark — clay/rust gradient square + Fraunces wordmark.
//

import SwiftUI

/// The clay→rust gradient square with the mountain glyph.
/// Used in topbars, splash screens, etc.
struct BrandMarkIcon: View {
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.clay, .rust],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )

            // Mountain glyph: M3 20h18 / M5 20l7-13 7 13 / M9 14l3-5.5 3 5.5
            Path { p in
                let s = size / 24.0
                p.move(to: CGPoint(x: 3*s, y: 20*s))
                p.addLine(to: CGPoint(x: 21*s, y: 20*s))

                p.move(to: CGPoint(x: 5*s, y: 20*s))
                p.addLine(to: CGPoint(x: 12*s, y: 7*s))
                p.addLine(to: CGPoint(x: 19*s, y: 20*s))

                p.move(to: CGPoint(x: 9*s, y: 14*s))
                p.addLine(to: CGPoint(x: 12*s, y: 8.5*s))
                p.addLine(to: CGPoint(x: 15*s, y: 14*s))
            }
            .stroke(Color.clayInk, style: StrokeStyle(lineWidth: size * 0.067, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.18), radius: 1)
    }
}

/// "Nomad" + italic clay "AI" wordmark.
struct BrandWordmark: View {
    var size: CGFloat = 22

    var body: some View {
        // Plain Text composition with two segments — preserves italic emphasis.
        (
            Text("Nomad")
                .font(.frauncesTitle(size).weight(.semibold))
            +
            Text("AI")
                .font(.frauncesHero(size, italic: true))
                .foregroundColor(.clay)
        )
        .kerning(-0.2)
        .lineLimit(1)
    }
}

/// Full topbar brand: icon + wordmark + mono caption stacked on the right.
struct BrandMark: View {
    var caption: String = "Field journal"

    var body: some View {
        HStack(spacing: 10) {
            BrandMarkIcon(size: 36)
            VStack(alignment: .leading, spacing: 2) {
                BrandWordmark(size: 20)
                Text(caption.uppercased())
                    .font(.mono(10, weight: .medium))
                    .tracking(1.2)
                    .foregroundStyle(.muted)
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        BrandMark()
        BrandMark(caption: "Search")
        BrandMarkIcon(size: 64)
    }
    .padding()
    .background(Color.bg)
    .preferredColorScheme(.dark)
}
