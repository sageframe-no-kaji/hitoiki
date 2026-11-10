import AppKit
import Carbon.HIToolbox
import Foundation
import Testing

@testable import Hitoiki

/// A user-defaults suite the test owns and removes: no test reads or writes the practitioner's preferences.
internal struct ThrowawaySuite {
    let name = "hitoiki-tests-" + UUID().uuidString
    let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: name))
    }

    /// The keys the suite's own domain holds, read from the domain itself.
    var keys: Set<String> {
        Set((defaults.persistentDomain(forName: name) ?? [:]).keys)
    }

    func remove() {
        defaults.removePersistentDomain(forName: name)
    }
}

/// The ten keys of ho-05.1 Decision 1, written out here rather than read from the code.
private let decisionOneKeys: Set<String> = [
    "shortcutKeyCode", "shortcutModifiers", "directoryMode", "directoryPath", "terminal", "appearance",
    "historyEnabled", "menuBarEnabled", "updateCheckEnabled", "macros",
]

/// Control-Command-Space in Carbon's numbers: `kVK_Space` is 49, `controlKey` 4096, `cmdKey` 256.
private let controlCommandSpace = Shortcut.Combination(keyCode: 49, modifiers: 4_096 + 256)

/// A value of every setting, none of them the default.
@MainActor
private func writeEverything(to settings: Settings) {
    settings.shortcut = Shortcut.Combination(keyCode: UInt32(kVK_ANSI_H), modifiers: UInt32(controlKey | optionKey))
    settings.directoryMode = .fixed
    settings.directoryPath = "/tmp/elsewhere"
    settings.terminal = "com.mitchellh.ghostty"
    settings.appearance = .dark
    settings.historyEnabled = true
    settings.menuBarEnabled = true
    settings.updateCheckEnabled = false
    var macros = settings.macros
    macros[0] = Macro(name: "uptime", command: "uptime")
    macros[8] = Macro(name: "", command: "ssh host-a")
    settings.macros = macros
}

@Suite("Settings")
@MainActor
internal struct SettingsTests {
    @Test("Absent, every key reads its default; reading every setting writes nothing")
    internal func defaults() throws {
        let suite = try ThrowawaySuite()
        defer { suite.remove() }
        let settings = Settings(defaults: suite.defaults)
        #expect(settings.shortcut == controlCommandSpace)
        #expect(settings.directoryMode == .home)
        #expect(settings.directoryPath == nil)
        #expect(settings.terminal == "com.apple.Terminal")
        #expect(settings.appearance == .system)
        #expect(!settings.historyEnabled)
        #expect(!settings.menuBarEnabled)
        #expect(settings.updateCheckEnabled)
        #expect(settings.macros == Array(repeating: Macro(name: "", command: ""), count: 9))
        #expect(suite.keys.isEmpty)
    }

    @Test("Each setting writes its own key and no other")
    internal func eachWritesItsKey() throws {
        let writes: [(keys: Set<String>, write: @MainActor (Settings) -> Void)] = [
            (["shortcutKeyCode", "shortcutModifiers"], { $0.shortcut = controlCommandSpace }),
            (["directoryMode"], { $0.directoryMode = .fixed }),
            (["directoryPath"], { $0.directoryPath = "/tmp" }),
            (["terminal"], { $0.terminal = "org.alacritty" }),
            (["appearance"], { $0.appearance = .light }),
            (["historyEnabled"], { $0.historyEnabled = true }),
            (["menuBarEnabled"], { $0.menuBarEnabled = true }),
            (["updateCheckEnabled"], { $0.updateCheckEnabled = false }),
            (["macros"], { $0.macros = [Macro(name: "a", command: "b")] }),
        ]
        for (keys, write) in writes {
            let suite = try ThrowawaySuite()
            defer { suite.remove() }
            write(Settings(defaults: suite.defaults))
            #expect(suite.keys == keys)
        }
    }

    @Test("Every setting round-trips through a second store over the same suite; the domain holds the ten keys")
    internal func roundTrip() throws {
        let suite = try ThrowawaySuite()
        defer { suite.remove() }
        writeEverything(to: Settings(defaults: suite.defaults))
        let second = Settings(defaults: try #require(UserDefaults(suiteName: suite.name)))
        #expect(second.shortcut == Shortcut.Combination(keyCode: 4, modifiers: 4_096 + 2_048))
        #expect(second.directoryMode == .fixed)
        #expect(second.directoryPath == "/tmp/elsewhere")
        #expect(second.terminal == "com.mitchellh.ghostty")
        #expect(second.appearance == .dark)
        #expect(second.historyEnabled)
        #expect(second.menuBarEnabled)
        #expect(!second.updateCheckEnabled)
        #expect(second.macros[0] == Macro(name: "uptime", command: "uptime"))
        #expect(second.macros[8] == Macro(name: "", command: "ssh host-a"))
        #expect(suite.keys == decisionOneKeys)

        // Back to the defaults, written as values, read back as written.
        second.directoryMode = .home
        second.directoryPath = nil
        second.appearance = .system
        second.updateCheckEnabled = true
        let third = Settings(defaults: try #require(UserDefaults(suiteName: suite.name)))
        #expect(third.directoryMode == .home)
        #expect(third.directoryPath == nil)
        #expect(third.appearance == .system)
        #expect(third.updateCheckEnabled)
        #expect(suite.keys == decisionOneKeys.subtracting(["directoryPath"]))
    }

    @Test("Macros: always nine; a written slot survives, an unwritten one reads empty; nine are stored")
    internal func macros() throws {
        let suite = try ThrowawaySuite()
        defer { suite.remove() }
        let settings = Settings(defaults: suite.defaults)
        settings.macros = [Macro(name: "one", command: "echo 1"), Macro(name: "two", command: "echo 2")]
        let read = Settings(defaults: suite.defaults).macros
        #expect(read.count == 9)
        #expect(read[0] == Macro(name: "one", command: "echo 1"))
        #expect(read[1] == Macro(name: "two", command: "echo 2"))
        #expect(read[2...].allSatisfy { $0 == Macro(name: "", command: "") })
        #expect((suite.defaults.array(forKey: "macros") as? [[String: String]])?.count == 9)

        settings.macros = (1...12).map { Macro(name: "", command: "echo \($0)") }
        #expect(Settings(defaults: suite.defaults).macros.map(\.command) == (1...9).map { "echo \($0)" })
        #expect((suite.defaults.array(forKey: "macros") as? [[String: String]])?.count == 9)

        // A stored array of another shape still reads as nine slots, the readable ones kept.
        suite.defaults.set([["command": "kept"]], forKey: "macros")
        #expect(settings.macros.count == 9)
        #expect(settings.macros[0] == Macro(name: "", command: "kept"))
    }

    @Test("A stored value outside a setting's values reads as its default")
    internal func unknownValues() throws {
        let suite = try ThrowawaySuite()
        defer { suite.remove() }
        suite.defaults.set("last-used", forKey: "directoryMode")
        suite.defaults.set("sepia", forKey: "appearance")
        suite.defaults.set("not a number", forKey: "shortcutKeyCode")
        let settings = Settings(defaults: suite.defaults)
        #expect(settings.directoryMode == .home)
        #expect(settings.appearance == .system)
        #expect(settings.shortcut == controlCommandSpace)
    }

    @Test("Appearance: system follows the system, light is Aqua, dark is Dark Aqua")
    internal func appearanceMapping() {
        #expect(Appearance.system.nsAppearance == nil)
        #expect(Appearance.light.nsAppearance?.name == .aqua)
        #expect(Appearance.dark.nsAppearance?.name == .darkAqua)
    }

    @Test("A live effect follows its setting: applied now, then with each new value, and not for another setting")
    internal func follow() async throws {
        let suite = try ThrowawaySuite()
        defer { suite.remove() }
        let settings = Settings(defaults: suite.defaults)
        let seen = Seen()
        settings.follow({ $0.appearance }, apply: { seen.values.append($0) })
        #expect(seen.values == [.system])
        settings.appearance = .dark
        try await until { seen.values == [.system, .dark] }
        settings.appearance = .light
        try await until { seen.values == [.system, .dark, .light] }
        settings.terminal = "org.alacritty"
        settings.appearance = .system
        try await until { seen.values == [.system, .dark, .light, .system] }
    }

    @Test("The settings window is one instance for the app's life: closed, it comes back the same window")
    internal func oneWindow() throws {
        let suite = try ThrowawaySuite()
        defer { suite.remove() }
        let app = HitoikiApp(settings: Settings(defaults: suite.defaults))
        app.showSettings(nil)
        let first = try #require(app.settingsWindow)
        defer { first.orderOut(nil) }
        #expect(first.isVisible)
        #expect(first.title == "Hitoiki Settings")
        app.showSettings(nil)
        #expect(app.settingsWindow === first)
        first.performClose(nil)
        #expect(!first.isVisible)
        app.showSettings(nil)
        #expect(app.settingsWindow === first)
        #expect(first.isVisible)
        #expect(NSApplication.shared.windows.filter { $0 is SettingsWindow && $0.isVisible }.count == 1)
    }
}

/// What a followed effect was applied with, in order.
@MainActor
private final class Seen {
    var values: [Appearance] = []
}

/// Waits, between main-actor jobs, until `condition` holds; ten seconds is a failure, not a pause.
@MainActor
private func until(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(10)
    while !condition() {
        try #require(ContinuousClock.now < deadline, "waited ten seconds")
        try await Task.sleep(for: .milliseconds(5))
    }
}
