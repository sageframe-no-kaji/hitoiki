import AppKit
import Testing

@testable import Hitoiki

/// The six terminals of ho-03 Decision 12, written out here rather than read from the code.
private let decisionTwelve = [
    "com.apple.Terminal", "com.mitchellh.ghostty", "com.googlecode.iterm2", "net.kovidgoyal.kitty",
    "com.github.wez.wezterm", "org.alacritty",
]

@Suite("Terminals")
@MainActor
internal struct TerminalsTests {
    @Test("The list is Decision 12's six, Terminal.app first")
    internal func known() {
        #expect(Terminals.known == decisionTwelve)
    }

    @Test("Detection returns Terminal.app on any Mac, every installed one of the six in order, and only those")
    internal func detection() {
        let installed = Terminals.installed()
        #expect(installed.first == "com.apple.Terminal")
        let resolving = decisionTwelve.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
        #expect(installed == resolving)
    }

    @Test("A resolved identifier is shown by the app's name; an unresolved one as itself, not installed")
    internal func names() {
        #expect(Terminals.name(of: "com.apple.Terminal") == "Terminal")
        #expect(Terminals.name(of: "org.example.no-such-terminal") == "org.example.no-such-terminal (not installed)")
        #expect(Terminals.url(for: "org.example.no-such-terminal") == nil)
    }

    @Test("Other…: an application's bundle identifier is read from it; a folder that is not one has none")
    internal func identifier() throws {
        let terminal = try #require(NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal"))
        #expect(Terminals.identifier(ofApplicationAt: terminal) == "com.apple.Terminal")
        #expect(Terminals.identifier(ofApplicationAt: URL(fileURLWithPath: NSTemporaryDirectory())) == nil)
    }
}
