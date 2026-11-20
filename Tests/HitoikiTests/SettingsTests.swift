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

/// Waits, between main-actor jobs, until `condition` holds; ten seconds is a failure, not a pause.
///
/// The settings and menu bar suites both wait with it.
@MainActor
internal func until(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(10)
    while !condition() {
        try #require(ContinuousClock.now < deadline, "waited ten seconds")
        try await Task.sleep(for: .milliseconds(5))
    }
}

/// The eleven keys the store writes, written out here rather than read from the code.
internal let settingsKeys: Set<String> = [
    "shortcutKeyCode", "shortcutModifiers", "directoryMode", "directoryPath", "terminal", "appearance",
    "historyEnabled", "menuBarEnabled", "updateCheckEnabled", "macros", "welcomeShown",
]

/// Control-Command-Space in Carbon's numbers: `kVK_Space` is 49, `controlKey` 4096, `cmdKey` 256.
private let controlCommandSpace = Shortcut.Combination(keyCode: 49, modifiers: 4_096 + 256)

/// A value of every setting, none of them the default.
@MainActor
internal func writeEverything(to settings: Settings) {
    settings.shortcut = Shortcut.Combination(keyCode: UInt32(kVK_ANSI_H), modifiers: UInt32(controlKey | optionKey))
    settings.directoryMode = .fixed
    settings.directoryPath = "/tmp/elsewhere"
    settings.terminal = "com.mitchellh.ghostty"
    settings.appearance = .dark
    settings.historyEnabled = true
    settings.menuBarEnabled = false
    settings.updateCheckEnabled = false
    var macros = settings.macros
    macros[0] = "uptime"
    macros[8] = "ssh host-a"
    settings.macros = macros
    settings.welcomeShown = true
}

@Suite("Settings", .serialized)
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
        #expect(settings.menuBarEnabled)
        #expect(settings.updateCheckEnabled)
        #expect(settings.macros == Array(repeating: "", count: 9))
        #expect(!settings.welcomeShown)
        #expect(suite.keys.isEmpty)
    }

    @Test("The menu bar item: on when its key is absent, off for a stored false, on for a stored true")
    internal func menuBarDefault() throws {
        let suite = try ThrowawaySuite()
        defer { suite.remove() }
        #expect(Settings(defaults: suite.defaults).menuBarEnabled)
        #expect(suite.keys.isEmpty)
        suite.defaults.set(false, forKey: "menuBarEnabled")
        #expect(!Settings(defaults: suite.defaults).menuBarEnabled)
        suite.defaults.set(true, forKey: "menuBarEnabled")
        #expect(Settings(defaults: suite.defaults).menuBarEnabled)
    }

    @Test("The store's keys are the eleven, welcomeShown among them")
    internal func keyList() {
        #expect(Set(Settings.Key.allCases.map(\.rawValue)) == settingsKeys)
        #expect(Settings.Key.allCases.count == 11)
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
            (["menuBarEnabled"], { $0.menuBarEnabled = false }),
            (["updateCheckEnabled"], { $0.updateCheckEnabled = false }),
            (["macros"], { $0.macros = ["b"] }),
            (["welcomeShown"], { $0.welcomeShown = true }),
        ]
        for (keys, write) in writes {
            let suite = try ThrowawaySuite()
            defer { suite.remove() }
            write(Settings(defaults: suite.defaults))
            #expect(suite.keys == keys)
        }
    }

    @Test("Every setting round-trips through a second store over the same suite; the domain holds the eleven keys")
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
        #expect(!second.menuBarEnabled)
        #expect(!second.updateCheckEnabled)
        #expect(second.macros[0] == "uptime")
        #expect(second.macros[8] == "ssh host-a")
        #expect(second.welcomeShown)
        #expect(suite.keys == settingsKeys)

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
        #expect(suite.keys == settingsKeys.subtracting(["directoryPath"]))
    }

    @Test("Macros: nine command strings always; a written slot survives, an unwritten one reads empty; nine are stored")
    internal func macros() throws {
        let suite = try ThrowawaySuite()
        defer { suite.remove() }
        let settings = Settings(defaults: suite.defaults)
        settings.macros = ["echo 1", "echo 2"]
        let read = Settings(defaults: suite.defaults).macros
        #expect(read == ["echo 1", "echo 2", "", "", "", "", "", "", ""])
        #expect(suite.defaults.array(forKey: "macros") as? [String] == read)

        settings.macros = (1...12).map { "echo \($0)" }
        #expect(Settings(defaults: suite.defaults).macros == (1...9).map { "echo \($0)" })
        #expect((suite.defaults.array(forKey: "macros") as? [String])?.count == 9)

        // A slot changed alone: the others are as they were.
        settings.macros[4] = "uptime"
        #expect(Settings(defaults: suite.defaults).macros[4] == "uptime")
        #expect(Settings(defaults: suite.defaults).macros[3] == "echo 4")
    }

    @Test("Macros: the first build's array of {name, command} dictionaries reads as nine empty slots")
    internal func macrosFromTheFirstBuild() throws {
        let suite = try ThrowawaySuite()
        defer { suite.remove() }
        let firstBuild: [[String: String]] =
            [["name": "uptime", "command": "uptime"], ["name": "", "command": "ssh host-a"]]
            + Array(repeating: ["name": "", "command": ""], count: 7)
        suite.defaults.set(firstBuild, forKey: "macros")
        let settings = Settings(defaults: suite.defaults)
        #expect(settings.macros == Array(repeating: "", count: 9))

        // The next write stores the new shape, nine strings, over the old.
        settings.macros[0] = "df -h"
        #expect(suite.defaults.array(forKey: "macros") as? [String] == ["df -h", "", "", "", "", "", "", "", ""])
        #expect(Settings(defaults: suite.defaults).macros[0] == "df -h")

        // Entries of mixed shape: each that is not a string reads empty in its own place.
        suite.defaults.set([["command": "old"], "kept", 7, "also kept"], forKey: "macros")
        #expect(settings.macros == ["", "kept", "", "also kept", "", "", "", "", ""])
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
}

/// What a followed effect was applied with, in order.
@MainActor
private final class Seen {
    var values: [Appearance] = []
}
