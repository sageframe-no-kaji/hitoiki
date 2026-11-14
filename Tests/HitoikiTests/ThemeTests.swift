import Testing

@testable import Hitoiki

@Suite("Theme")
internal struct ThemeTests {
    /// The eight tokens, in the design system's row order.
    private static let tokens: [Palette] = [
        Theme.Token.ground,
        Theme.Token.groundDeep,
        Theme.Token.ink,
        Theme.Token.inkFaint,
        Theme.Token.accent,
        Theme.Token.panelGround,
        Theme.Token.alarm,
        Theme.Token.plugin,
    ]

    /// The three transcript colours derived from them.
    private static let transcriptTokens: [Palette] = [
        Theme.Token.transcriptBlue,
        Theme.Token.transcriptMagenta,
        Theme.Token.transcriptCyan,
    ]

    /// The design system's §2 table, row by row: hex and opacity.
    private static let designSystem: [(hex: String, alpha: Double)] = [
        ("#FAF7F3", 1),
        ("#F4F1EA", 1),
        ("#1D1B18", 1),
        ("#1D1B18", 0.55),
        ("#5A7552", 1),
        ("#EDEEF1", 1),
        ("#984D3C", 1),
        ("#945C2E", 1),
    ]

    /// Within 0.002 of the hex: half of one 8-bit step (1/510), so pālana's two-place `plugin` digits still match.
    @Test("Light values match the design system's hex", arguments: zip(tokens, designSystem))
    internal func lightMatchesDesignSystem(token: Palette, row: (hex: String, alpha: Double)) throws {
        let rgb = try #require(Int(row.hex.dropFirst(), radix: 16))
        let light = token.light
        #expect(abs(light.red - Double((rgb >> 16) & 0xFF) / 255) <= 0.002)
        #expect(abs(light.green - Double((rgb >> 8) & 0xFF) / 255) <= 0.002)
        #expect(abs(light.blue - Double(rgb & 0xFF) / 255) <= 0.002)
        #expect(abs(light.alpha - row.alpha) <= 0.002)
    }

    @Test("resolved(dark:) returns the matching member", arguments: tokens + transcriptTokens)
    internal func resolvedPicksAppearance(token: Palette) {
        #expect(token.resolved(dark: true) == token.dark)
        #expect(token.resolved(dark: false) == token.light)
    }

    @Test("No dark value is pure black or pure white", arguments: tokens + transcriptTokens)
    internal func darkIsNeverPure(token: Palette) {
        let dark = token.dark
        let channels = [dark.red, dark.green, dark.blue]
        #expect(channels.contains { $0 > 0.05 && $0 < 0.95 })
    }

    @Test("The transcript colours are opaque, and lifted toward bright in dark", arguments: transcriptTokens)
    internal func transcriptLift(token: Palette) {
        let light = token.resolved(dark: false)
        let dark = token.resolved(dark: true)
        #expect(light.alpha == 1)
        #expect(dark.alpha == 1)
        #expect(dark.red > light.red)
        #expect(dark.green > light.green)
        #expect(dark.blue > light.blue)
    }

    @Test("The colour table has eight entries: 0 ink, 1 alarm, 2 accent, 3 plugin, 4–6 derived, 7 inkFaint")
    internal func colourTable() {
        #expect(
            Theme.transcriptColors == [
                Theme.Token.ink, Theme.Token.alarm, Theme.Token.accent, Theme.Token.plugin,
                Theme.Token.transcriptBlue, Theme.Token.transcriptMagenta, Theme.Token.transcriptCyan,
                Theme.Token.inkFaint,
            ])
        #expect(Theme.transcriptColors.count == 8)
        #expect(Theme.transcriptColors[1] == Theme.Token.alarm)
        #expect(Theme.transcriptColors[2] == Theme.Token.accent)
    }
}
