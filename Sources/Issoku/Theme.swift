// The panel's palette — warm quiet ground, near-black ink, one moss accent,
// one rust alarm, one umber category tint, and three transcript colours.
// Every token is appearance-aware: a light value and a warm-dark sibling,
// resolved with no asset catalog.
//
// The eight light values are copied from `palana/design/palana-design-system.md`
// §2. Their dark values are copied from pālana's `Sources/Palana/Theme.swift`,
// its ho-15 port of Sharibako's dark mode. pālana is the source of truth for
// both; a change there is copied here, never made here first. The three
// transcript colours are Issoku's own, derived from those eight (ho-04
// Decision 2).
//
// The pure `resolved(dark:)` seam is unit-tested per token, so the palette
// carries real coverage even though the app target sits outside the floor.
// AppKit only: the panel has no SwiftUI (ho-04, Rules for the subagent).

import AppKit

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
}

/// The surface's colors — appearance-aware tokens, per the design language.
internal enum Theme {
    /// The eight basic colours of SGR `30`–`37`, by index, for the transcript (ho-04 Decision 2).
    internal static let transcriptColors: [Palette] = [
        Token.ink,
        Token.alarm,
        Token.accent,
        Token.plugin,
        Token.transcriptBlue,
        Token.transcriptMagenta,
        Token.transcriptCyan,
        Token.inkFaint,
    ]

    /// The light/dark values per token — the pure, unit-tested seam.
    ///
    /// The first eight are copied digit for digit from pālana's `Theme.Token`.
    /// Light is design system §2; dark is pālana's Sharibako port, with
    /// `plugin`'s dark derived there by the same "lift toward warm + bright"
    /// ratio the accent and alarm pairs show. The three transcript tokens
    /// after them are derived here.
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

        // The three transcript colours pālana has no token for, derived in OKLCH. Light: the mean
        // lightness of moss, rust and umber (L 0.5224), moss's chroma (C 0.0619, the lowest of the
        // three, so muted), and the hue of the sRGB primary turned 10° toward the ground's warm hue
        // (75°) — the warm shift. Dark: the mean lift the accent, alarm and plugin pairs show
        // (L +0.1294, C ×1.0846, hue +2.0°), the same lift toward warm and bright.

        /// Slate blue, for SGR 34: hue 264.05° turned to 274.05° (dark 276.05°).
        internal static let transcriptBlue = Palette(
            light: RGBA(red: 0.3698, green: 0.4046, blue: 0.5558, alpha: 1),
            dark: RGBA(red: 0.5184, green: 0.5515, blue: 0.7259, alpha: 1))

        /// Plum, for SGR 35: hue 328.36° turned to 338.36° (dark 340.36°).
        internal static let transcriptMagenta = Palette(
            light: RGBA(red: 0.5081, green: 0.3599, blue: 0.4623, alpha: 1),
            dark: RGBA(red: 0.6758, green: 0.5015, blue: 0.6135, alpha: 1))

        /// Muted teal, for SGR 36: hue 194.77° turned to 184.77° (dark 186.77°).
        internal static let transcriptCyan = Palette(
            light: RGBA(red: 0.2346, green: 0.4604, blue: 0.4316, alpha: 1),
            dark: RGBA(red: 0.3649, green: 0.6170, blue: 0.5895, alpha: 1))
    }
}
