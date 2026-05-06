//
//  Tokens.swift
//  NomadAI — Design Tokens
//
//  All values lifted from `NomadAI Redesign.html`. See docs/design-tokens.md.
//

import SwiftUI

// MARK: - Color Tokens

extension Color {
    // Surfaces
    static var bg:        Color { Color("bg") }        // page background
    static var bark:      Color { Color("bark") }      // card base
    static var surface:   Color { Color("surface") }   // raised
    static var surface2:  Color { Color("surface2") }  // doubly-raised
    static var line:      Color { Color("line") }      // hairline
    static var lineSoft:  Color { Color("lineSoft") }  // soft hairline

    // Foreground
    static var fg:        Color { Color("fg") }        // primary text
    static var fgDim:     Color { Color("fgDim") }     // secondary
    static var muted:     Color { Color("muted") }     // tertiary
    static var faint:     Color { Color("faint") }     // quaternary

    // Accents
    static var clay:      Color { Color("clay") }      // primary accent
    static var clayInk:   Color { Color("clayInk") }   // text on clay
    static var moss:      Color { Color("moss") }      // secondary accent
    static var sage:      Color { Color("sage") }
    static var rust:      Color { Color("rust") }
    static var sand:      Color { Color("sand") }
    static var slate:     Color { Color("slate") }
    static var sky:       Color { Color("sky") }
    static var berry:     Color { Color("berry") }     // destructive

    // Source brand colors
    static var dyrt:      Color { Color("dyrt") }
    static var rec:       Color { Color("rec") }
    static var iov:       Color { Color("iov") }
    static var blm:       Color { Color("blm") }
    static var camp:      Color { Color("camp") }
}

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
