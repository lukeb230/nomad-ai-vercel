//
//  Typography.swift
//  NomadAI — Type System
//
//  Three families: Fraunces (display), Inter Tight (UI), JetBrains Mono (micro-labels).
//
//  Setup:
//  1. Download font files from Google Fonts:
//     - Fraunces (variable, full axes including SOFT)
//     - Inter Tight (weights 400-700)
//     - JetBrains Mono (weights 400-700)
//  2. Drop the .ttf or .otf files into Sources/NomadAI/Resources/Fonts/
//  3. Add each filename to Info.plist under `UIAppFonts` array
//

import SwiftUI

// MARK: - Font Families (raw names)

enum FontFamily {
    static let fraunces = "Fraunces"
    static let frauncesItalic = "Fraunces-Italic"
    static let interTight = "InterTight"
    static let mono = "JetBrainsMono"
}

// MARK: - Type Scale

extension Font {
    // ---- DISPLAY (Fraunces) ----

    /// Home/auth screen big headline. ~36-40pt, italic-emphasis variant.
    static func frauncesHero(_ size: CGFloat = 36, italic: Bool = false) -> Font {
        .custom(italic ? FontFamily.frauncesItalic : FontFamily.fraunces, size: size).weight(.regular)
    }

    /// Modal titles and section headlines. ~22-30pt.
    static func frauncesTitle(_ size: CGFloat = 22) -> Font {
        .custom(FontFamily.fraunces, size: size).weight(.medium)
    }

    /// Card name (campsite, journal entry). ~16-19pt.
    static func frauncesCard(_ size: CGFloat = 19) -> Font {
        .custom(FontFamily.fraunces, size: size).weight(.medium)
    }

    /// Stats numerals. Same Fraunces medium weight.
    static func frauncesNumeral(_ size: CGFloat = 28) -> Font {
        .custom(FontFamily.fraunces, size: size).weight(.medium)
    }

    // ---- BODY (Inter Tight) ----

    static func body(_ size: CGFloat = 14, weight: Font.Weight = .medium) -> Font {
        .custom(FontFamily.interTight, size: size).weight(weight)
    }

    static var bodyLg: Font { body(14, weight: .medium) }
    static var bodyMd: Font { body(13, weight: .medium) }
    static var bodySm: Font { body(12, weight: .medium) }
    static var bodyXs: Font { body(11, weight: .medium) }

    // ---- MONO (JetBrains Mono) — labels, eyebrows, micro-text ----

    static func mono(_ size: CGFloat = 10, weight: Font.Weight = .medium) -> Font {
        .custom(FontFamily.mono, size: size).weight(weight)
    }

    /// Mono label — section headers, eyebrows. Use uppercase + .tracking.
    static var monoLabel: Font { mono(10, weight: .medium) }

    /// Mono value — distance, mileage, %.
    static var monoValue: Font { mono(11, weight: .semibold) }
}

// MARK: - Convenient text styles

extension Text {
    /// Use for the mono uppercase eyebrows (e.g. "FIELD JOURNAL", "CURRENT TRIP").
    func monoLabel() -> some View {
        self.font(.monoLabel)
            .tracking(1.8)               // ~0.18em at 10pt
            .textCase(.uppercase)
            .foregroundStyle(Color.muted)
    }

    /// Big editorial headline.
    func display(size: CGFloat = 36, italic: Bool = false) -> Text {
        self.font(.frauncesHero(size, italic: italic))
            .kerning(-1.0)               // ~-0.03em letter-spacing
    }

    /// Card title.
    func cardName() -> Text {
        self.font(.frauncesCard())
            .kerning(-0.2)
    }
}

// MARK: - Helper for italic-emphasis Fraunces inline

/// Builds a Text composition like "Where to, *this weekend*?" with italic clay emphasis.
/// Usage:
///   FrauncesEmphasis(prefix: "Where to, ", italic: "this weekend", suffix: "?", size: 36)
struct FrauncesEmphasis: View {
    let prefix: String
    let italic: String
    let suffix: String
    var size: CGFloat = 36

    var body: some View {
        (
            Text(prefix).font(.frauncesHero(size))
            + Text(italic).font(.frauncesHero(size, italic: true))
                .foregroundColor(.clay)
            + Text(suffix).font(.frauncesHero(size))
        )
        .kerning(-1.0)
    }
}
