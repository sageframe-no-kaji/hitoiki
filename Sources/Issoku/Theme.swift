// The panel's palette — warm quiet ground, near-black ink, one moss accent,
// one rust alarm, one umber category tint. Every token is appearance-aware:
// a light value and a warm-dark sibling, resolved with no asset catalog.
//
// The light values are copied from `palana/design/palana-design-system.md`
// §2. The dark values are copied from pālana's `Sources/Palana/Theme.swift`,
// its ho-15 port of Sharibako's dark mode. pālana is the source of truth for
// both; a change there is copied here, never made here first.
//
// The pure `resolved(dark:)` seam is unit-tested per token, so the palette
// carries real coverage even though the app target sits outside the floor.

import AppKit
import SwiftUI

/// A single sRGB color with alpha, as plain `Double` components.
///
/// `Sendable` by construction (all `Double`), so the dynamic-`NSColor`
/// provider closure can capture it without crossing a concurrency boundary
/// with a non-`Sendable` `NSColor`.
internal struct RGBA: Sendable, Equatable {
    internal let red: Double
    internal let green: Double
    internal let blue: Double
    internal let alpha: Double

    /// The concrete `NSColor` for these components, in the sRGB space.
    internal var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

/// A token's light and dark values, and the machinery to resolve between them.
internal struct Palette: Sendable, Equatable {
    /// The value in light appearance (pālana design system §2).
    internal let light: RGBA
    /// The value in dark appearance (pālana's ho-15 port of Sharibako).
    internal let dark: RGBA

    /// The raw components for a given appearance — the pure, tested seam both
    /// the dynamic color and the tests read, so neither drifts from the other.
    internal func resolved(dark isDark: Bool) -> RGBA {
        isDark ? dark : light
    }

    /// An appearance-aware `NSColor` that re-resolves on appearance change.
    ///
    /// No asset catalog — the dynamic provider re-runs whenever the effective
    /// appearance flips; the closure captures only the `Sendable` `self`.
    internal var nsColor: NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return resolved(dark: isDark).nsColor
        }
    }

    /// The SwiftUI `Color` the views consume.
    internal var color: Color {
        Color(nsColor: nsColor)
    }
}

/// The surface's colors — appearance-aware tokens, per the design language.
internal enum Theme {
    // Each token is resolved ONCE into a `Color` that wraps a *dynamic*
    // `NSColor` — so it stays appearance-aware (re-resolving on the light/dark
    // flip) while costing nothing per access. In pālana, computed accessors
    // allocated a fresh dynamic `NSColor` on every read, which per-cell color
    // reads turned into a navigation stutter (pālana ho-13/15 review). `let`,
    // not `var`, is the fix.

    /// The paper every view sits on.
    internal static let ground: Color = Token.ground.color

    /// Headers, footers, key-cap chips — a shade down from ground.
    internal static let groundDeep: Color = Token.groundDeep.color

    /// Primary text.
    internal static let ink: Color = Token.ink.color

    /// Secondary facts — paths, dates, counts, hint lines, hairlines.
    internal static let inkFaint: Color = Token.inkFaint.color

    /// The one interactive color — quiet moss.
    internal static let accent: Color = Token.accent.color

    /// The "data" surface — notebook gone a shade cooler (a ~5% slate).
    internal static let panelGround: Color = Token.panelGround.color

    /// Quiet rust.
    internal static let alarm: Color = Token.alarm.color

    /// Burnt umber — one extra category tint that reads distinct from accent and alarm.
    internal static let plugin: Color = Token.plugin.color

    /// The light/dark values per token — the pure, unit-tested seam.
    ///
    /// Light and dark are copied digit for digit from pālana's `Theme.Token`.
    /// Light is design system §2; dark is pālana's Sharibako port, with
    /// `plugin`'s dark derived there by the same "lift toward warm + bright"
    /// ratio the accent and alarm pairs show.
    internal enum Token {
        internal static let ground = Palette(
            light: RGBA(red: 0.9804, green: 0.9686, blue: 0.9529, alpha: 1),
            dark: RGBA(red: 0.1059, green: 0.1020, blue: 0.0902, alpha: 1))

        internal static let groundDeep = Palette(
            light: RGBA(red: 0.9569, green: 0.9451, blue: 0.9176, alpha: 1),
            dark: RGBA(red: 0.1412, green: 0.1333, blue: 0.1176, alpha: 1))

        internal static let ink = Palette(
            light: RGBA(red: 0.1137, green: 0.1059, blue: 0.0941, alpha: 1),
            dark: RGBA(red: 0.9255, green: 0.9059, blue: 0.8745, alpha: 1))

        internal static let inkFaint = Palette(
            light: RGBA(red: 0.1137, green: 0.1059, blue: 0.0941, alpha: 0.55),
            dark: RGBA(red: 0.9255, green: 0.9059, blue: 0.8745, alpha: 0.60))

        internal static let accent = Palette(
            light: RGBA(red: 0.3529, green: 0.4588, blue: 0.3216, alpha: 1),
            dark: RGBA(red: 0.4941, green: 0.6078, blue: 0.4471, alpha: 1))

        internal static let panelGround = Palette(
            light: RGBA(red: 0.9294, green: 0.9333, blue: 0.9451, alpha: 1),
            dark: RGBA(red: 0.1255, green: 0.1333, blue: 0.1647, alpha: 1))

        internal static let alarm = Palette(
            light: RGBA(red: 0.5961, green: 0.3020, blue: 0.2353, alpha: 1),
            dark: RGBA(red: 0.7725, green: 0.4196, blue: 0.3412, alpha: 1))

        internal static let plugin = Palette(
            light: RGBA(red: 0.58, green: 0.36, blue: 0.18, alpha: 1),
            dark: RGBA(red: 0.75, green: 0.54, blue: 0.32, alpha: 1))
    }
}
