//
//  Tokens.swift
//  NomadAI — Design Tokens
//
//  All values lifted from `NomadAI Redesign.html`. See docs/design-tokens.md.
//

import SwiftUI

// MARK: - Color Tokens
//
// Color symbols (Color.bg, Color.bark, Color.clay, etc.) are auto-generated
// by Xcode 15+ from Assets.xcassets. The build phase emits a synthetic
// `GeneratedAssetSymbols.swift` that adds a `static var <name>: Color` for
// every color set. To add a new token, just add a new .colorset to the
// asset catalog and rebuild.
//
// Token reference (see docs/design-tokens.md for hex values + light variants):
//
//   Surfaces:   bg, bark, surface, surface2, line, lineSoft
//   Foreground: fg, fgDim, muted, faint
//   Accents:    clay, clayInk, moss, sage, rust, sand, slate, sky, berry
//   Sources:    dyrt, rec, iov, blm, camp

// MARK: - Spacing

enum Spacing {
    static let xs:  CGFloat = 4
    static let sm:  CGFloat = 6
    static let md:  CGFloat = 10
    static let lg:  CGFloat = 14
    static let xl:  CGFloat = 20
    static let xxl: CGFloat = 28

    /// Standard horizontal padding for tab pages
    static let pageHorizontal: CGFloat = 16
}

// MARK: - Corner Radii

enum Radius {
    static let pill: CGFloat = 999
    static let lg:   CGFloat = 18
    static let md:   CGFloat = 14
    static let sm:   CGFloat = 10
    static let xs:   CGFloat = 6
}

// MARK: - Shadow tokens

extension View {
    /// Subtle shadow for cards
    func shadowSm() -> some View {
        self.shadow(color: .black.opacity(0.28), radius: 1, y: 1)
    }

    /// Mid shadow for raised surfaces (modals, hero cards)
    func shadowMd() -> some View {
        self.shadow(color: .black.opacity(0.4), radius: 10, y: 4)
    }

    /// Heavy shadow for elevated overlays
    func shadowLg() -> some View {
        self.shadow(color: .black.opacity(0.5), radius: 24, y: 8)
    }
}

// MARK: - Source Color Helper

enum CampsiteSource: String, Codable {
    case dyrt, recreationGov = "recreation.gov", ioverlander, blm, campendium, other

    var brandColor: Color {
        switch self {
        case .dyrt: return .dyrt
        case .recreationGov: return .rec
        case .ioverlander: return .iov
        case .blm: return .blm
        case .campendium: return .camp
        case .other: return .slate
        }
    }

    var label: String {
        switch self {
        case .dyrt: return "The Dyrt"
        case .recreationGov: return "Recreation.gov"
        case .ioverlander: return "iOverlander"
        case .blm: return "BLM"
        case .campendium: return "Campendium"
        case .other: return "Other"
        }
    }
}
