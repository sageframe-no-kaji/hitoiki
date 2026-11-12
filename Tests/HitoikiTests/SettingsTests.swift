// The Settings suite and the settings-window suite nested in the Panel suite, in the one test file the ho
// tables name for settings: the window suite cannot move to a second file, so the file runs past the length
// rule.
// swiftlint:disable file_length

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

/// A history in a folder inside a directory the test owns and removes, never the app's own folder.
@MainActor
private struct ThrowawayHistory {
    let root: URL
    let folder: URL
    let history: History

    /// History on or off as `settings` says.
    init(following settings: Settings) {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "hitoiki-settings-" + UUID().uuidString)
        folder = root.appending(path: "Hitoiki")
        history = History(folder: folder) { settings.historyEnabled }
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
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
    macros[0] = "uptime"
    macros[8] = "ssh host-a"
    settings.macros = macros
}

// Serialized, as it was when the window tests below were in it; they are now in the Panel suite.
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
        #expect(!settings.menuBarEnabled)
        #expect(settings.updateCheckEnabled)
        #expect(settings.macros == Array(repeating: "", count: 9))
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
            (["macros"], { $0.macros = ["b"] }),
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
        #expect(second.macros[0] == "uptime")
        #expect(second.macros[8] == "ssh host-a")
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

// The tests that show the settings window, nested in the Panel suite so they run one at a time with its
// tests: a settings window takes the keyboard, and the Panel suite reads the panel's key status across its
// awaits. Run beside each other, as two suites do, a window shown here took the keyboard from a running
// panel there (ho-05.2, run 2).
extension PanelTests {
    @Suite("Settings window")
    @MainActor
    internal struct SettingsWindowTests {
        @Test("The settings window is one instance for the app's life: closed, it comes back the same window")
        internal func oneWindow() throws {
            let suite = try ThrowawaySuite()
            defer { suite.remove() }
            let settings = Settings(defaults: suite.defaults)
            let scratch = ThrowawayHistory(following: settings)
            defer { scratch.remove() }
            let app = HitoikiApp(settings: settings, history: scratch.history)
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

        @Test("Escape hides the settings window as the close button does; the next Settings… brings the same one back")
        internal func escapeHides() throws {
            let suite = try ThrowawaySuite()
            defer { suite.remove() }
            let settings = Settings(defaults: suite.defaults)
            let scratch = ThrowawayHistory(following: settings)
            defer { scratch.remove() }
            let app = HitoikiApp(settings: settings, history: scratch.history)
            app.showSettings(nil)
            let window = try #require(app.settingsWindow)
            defer { window.orderOut(nil) }
            #expect(window.isVisible)

            // A modified Escape is not Escape.
            window.sendEvent(try escape(modifiers: .command, in: window))
            #expect(window.isVisible)

            window.sendEvent(try escape(in: window))
            #expect(!window.isVisible)
            app.showSettings(nil)
            #expect(app.settingsWindow === window)
            #expect(window.isVisible)
        }

        @Test("Escape while a macro's box has the keyboard still hides the window")
        internal func escapeFromAMacroBox() async throws {
            let suite = try ThrowawaySuite()
            defer { suite.remove() }
            let settings = Settings(defaults: suite.defaults)
            let scratch = ThrowawayHistory(following: settings)
            defer { scratch.remove() }
            let app = HitoikiApp(settings: settings, history: scratch.history)
            app.showSettings(nil)
            let window = try #require(app.settingsWindow)
            defer { window.orderOut(nil) }
            var box: NSTextField?
            try await until {
                box = descendants(of: window.contentView).compactMap { $0 as? NSTextField }.first(where: \.isEditable)
                return box != nil
            }
            let field = try #require(box)
            #expect(window.makeFirstResponder(field))
            #expect(window.firstResponder is NSTextView)
            window.sendEvent(try escape(in: window))
            #expect(!window.isVisible)
        }

        @Test("Escape while the recorder records cancels the recording and leaves the window; the next Escape hides it")
        internal func escapeWhileRecording() async throws {
            let suite = try ThrowawaySuite()
            defer { suite.remove() }
            let settings = Settings(defaults: suite.defaults)
            let scratch = ThrowawayHistory(following: settings)
            defer { scratch.remove() }
            let app = HitoikiApp(settings: settings, history: scratch.history)
            app.showSettings(nil)
            let window = try #require(app.settingsWindow)
            defer { window.orderOut(nil) }
            var found: RecorderView?
            try await until {
                found = descendants(of: window.contentView).compactMap { $0 as? RecorderView }.first
                return found != nil
            }
            let recorder = try #require(found)
            let click = try #require(
                NSEvent.mouseEvent(
                    with: .leftMouseDown,
                    location: .zero,
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    clickCount: 1,
                    pressure: 1))
            recorder.mouseDown(with: click)
            #expect(recorder.isRecording)

            window.sendEvent(try escape(in: window))
            #expect(!recorder.isRecording)
            #expect(window.isVisible)

            window.sendEvent(try escape(in: window))
            #expect(!window.isVisible)
        }

        // ho-05.2: Command-Q from settings (Decision 11), no new key in the defaults, the macro rows' spacing.

        @Test("Command-Q in the settings window sends the terminate selector to the application, whatever is focused")
        internal func commandQuit() async throws {
            let suite = try ThrowawaySuite()
            defer { suite.remove() }
            let settings = Settings(defaults: suite.defaults)
            let scratch = ThrowawayHistory(following: settings)
            defer { scratch.remove() }
            let app = HitoikiApp(settings: settings, history: scratch.history)
            app.showSettings(nil)
            let window = try #require(app.settingsWindow)
            defer { window.orderOut(nil) }
            // Unless a test stands in for it, the selector goes to the application itself.
            #expect(window.application === NSApplication.shared)
            let quit = Terminations()
            window.application = quit

            let commandQ = try keyDown("q", code: kVK_ANSI_Q, modifiers: .command, in: window)
            #expect(window.performKeyEquivalent(with: commandQ))
            #expect(quit.senders.count == 1)
            #expect((quit.senders.last as? SettingsWindow) === window)
            #expect(window.isVisible)

            // A macro's box has the keyboard: still Command-Q.
            let field = try #require(try await macroBoxes(in: window).first)
            #expect(window.makeFirstResponder(field))
            #expect(window.performKeyEquivalent(with: commandQ))
            #expect(quit.senders.count == 2)

            // Caps Lock on: still Command-Q. Option-Command-Q is not it.
            let capsLock = try keyDown("Q", code: kVK_ANSI_Q, modifiers: [.command, .capsLock], in: window)
            #expect(window.performKeyEquivalent(with: capsLock))
            #expect(quit.senders.count == 3)
            let optionQ = try keyDown("q", code: kVK_ANSI_Q, modifiers: [.command, .option], in: window)
            _ = window.performKeyEquivalent(with: optionQ)
            #expect(quit.senders.count == 3)
        }

        @Test("History, settings, About and a manual check leave the defaults with ho-05.1's ten keys alone")
        internal func noNewKey() async throws {
            let suite = try ThrowawaySuite()
            defer { suite.remove() }
            let settings = Settings(defaults: suite.defaults)
            writeEverything(to: settings)
            #expect(settings.historyEnabled)
            let scratch = ThrowawayHistory(following: settings)
            defer { scratch.remove() }
            let history = scratch.history
            history.record("echo one\n echo secret\necho two")
            #expect(history.entries == ["echo two", "echo one"])
            #expect(history.matches("ONE") == ["echo one"])
            #expect(history.suggestion(for: "echo t") == "wo")
            #expect(history.clear() == nil)
            let stand = FetchStandIn(tag: "v1.1")
            let check = UpdateCheck(version: "1.0.0", enabled: { settings.updateCheckEnabled }, fetch: stand.fetch)
            let app = HitoikiApp(settings: settings, history: history, updateCheck: check)
            app.showSettings(nil)
            app.checkForUpdates(nil)
            try await until { check.answer == .available("1.1") }
            app.showAbout(nil)
            app.aboutWindow?.orderOut(nil)
            app.settingsWindow?.orderOut(nil)
            #expect(suite.keys == decisionOneKeys)
            // The history file was the one file written, and Clear took it.
            #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.folder.path).isEmpty)
        }

        @Test("The nine macro rows: a box each, in order, at one pitch; the pitch is printed for the run sheet")
        internal func macroRows() async throws {
            let suite = try ThrowawaySuite()
            defer { suite.remove() }
            let settings = Settings(defaults: suite.defaults)
            settings.macros = (1...9).map { "echo \($0)" }
            let scratch = ThrowawayHistory(following: settings)
            defer { scratch.remove() }
            let app = HitoikiApp(settings: settings, history: scratch.history)
            app.showSettings(nil)
            let window = try #require(app.settingsWindow)
            defer { window.orderOut(nil) }
            // Tall enough that the form lays out every row.
            window.setContentSize(NSSize(width: 520, height: 1_600))
            let boxes = try await macroBoxes(in: window)
            #expect(boxes.count == 9)
            // Window coordinates rise upward: the first row is the highest.
            let rows = boxes.map { (frame: $0.convert($0.bounds, to: nil), text: $0.stringValue) }
                .sorted { $0.frame.minY > $1.frame.minY }
            #expect(rows.map(\.text) == (1...9).map { "echo \($0)" })
            let frames = rows.map(\.frame)
            let pitches = zip(frames, frames.dropFirst()).map { $0.minY - $1.minY }
            print("ho-05.2 macro rows: pitch \(pitches), box heights \(frames.map(\.height))")
            #expect(pitches.allSatisfy { abs($0 - pitches[0]) < 1 })
            // Decision 16: 32 points apart, a 5-point gap between the 27-point boxes.
            #expect(abs(pitches[0] - 32) < 0.5)
            #expect(frames.allSatisfy { abs($0.height - 27) < 0.5 })
        }

        // ho-05.2 Decisions 14 and 15, from the run sheet: Command-N goes to its macro's box; Command-comma does
        // nothing here.

        @Test("Command-1 puts the keyboard in macro 1's box, cursor at the end; Command-9, Caps Lock on, in macro 9's")
        internal func commandDigitFocusesMacro() async throws {
            let suite = try ThrowawaySuite()
            defer { suite.remove() }
            let settings = Settings(defaults: suite.defaults)
            let macros = (1...9).map { "echo \($0)" }
            settings.macros = macros
            let scratch = ThrowawayHistory(following: settings)
            defer { scratch.remove() }
            let app = HitoikiApp(settings: settings, history: scratch.history)
            app.showSettings(nil)
            let window = try #require(app.settingsWindow)
            defer { window.orderOut(nil) }
            let quit = Terminations()
            window.application = quit
            let boxes = try await macroBoxes(in: window)
            #expect(boxes.count == 9)

            let codes = [
                kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8,
                kVK_ANSI_9,
            ]
            for (slot, capsLock) in [(1, false), (9, true), (5, false)] {
                let modifiers: NSEvent.ModifierFlags = capsLock ? [.command, .capsLock] : .command
                let event = try keyDown("\(slot)", code: codes[slot - 1], modifiers: modifiers, in: window)
                #expect(window.performKeyEquivalent(with: event))
                let editor = try #require(window.firstResponder as? NSTextView)
                #expect(editor.delegate === boxes[slot - 1])
                #expect(editor.string == "echo \(slot)")
                #expect(editor.selectedRange() == NSRange(location: editor.string.utf16.count, length: 0))
            }
            // Nothing else changed: the macros, the window, and nothing sent to the application.
            #expect(settings.macros == macros)
            #expect(window.isVisible && app.settingsWindow === window)
            #expect(quit.senders.isEmpty)

            // Option-Command-1 is not it: the keyboard stays where it was.
            let before = window.firstResponder
            let optionOne = try keyDown("1", code: kVK_ANSI_1, modifiers: [.command, .option], in: window)
            _ = window.performKeyEquivalent(with: optionOne)
            #expect(window.firstResponder === before)
        }

        @Test("Command-comma in the settings window does nothing: the keyboard stays, nothing goes to the application")
        internal func commandCommaInSettings() async throws {
            let suite = try ThrowawaySuite()
            defer { suite.remove() }
            let settings = Settings(defaults: suite.defaults)
            settings.macros = ["echo 1"]
            let scratch = ThrowawayHistory(following: settings)
            defer { scratch.remove() }
            let app = HitoikiApp(settings: settings, history: scratch.history)
            app.showSettings(nil)
            let window = try #require(app.settingsWindow)
            defer { window.orderOut(nil) }
            let recorder = Terminations()
            window.application = recorder
            let field = try #require(try await macroBoxes(in: window).first)
            #expect(window.makeFirstResponder(field))
            let editor = try #require(window.firstResponder as? NSTextView)
            editor.setSelectedRange(NSRange(location: 2, length: 0))
            for modifiers: NSEvent.ModifierFlags in [.command, [.command, .capsLock]] {
                let comma = try keyDown(",", code: kVK_ANSI_Comma, modifiers: modifiers, in: window)
                #expect(window.performKeyEquivalent(with: comma))
                #expect(window.firstResponder === editor)
                #expect(editor.selectedRange() == NSRange(location: 2, length: 0))
                #expect(editor.string == "echo 1")
            }
            #expect(recorder.senders.isEmpty && recorder.settings.isEmpty)
            #expect(window.isVisible && app.settingsWindow === window)
        }
    }
}

// ho-06.1 Decisions 7 to 9: the footer, Check for Updates… from the menu, and the one About window; in the
// settings-window suite, which runs inside the Panel suite, one test at a time.
extension PanelTests.SettingsWindowTests {
    @Test("The footer, outside the scrolling form: About Hitoiki shows About; Check for Updates checks")
    internal func footer() async throws {
        let suite = try ThrowawaySuite()
        defer { suite.remove() }
        let settings = Settings(defaults: suite.defaults)
        settings.updateCheckEnabled = false
        let scratch = ThrowawayHistory(following: settings)
        defer { scratch.remove() }
        let stand = FetchStandIn(tag: "v1.0.0")
        let check = UpdateCheck(version: "1.0.0", enabled: { settings.updateCheckEnabled }, fetch: stand.fetch)
        let app = HitoikiApp(settings: settings, history: scratch.history, updateCheck: check)
        app.showSettings(nil)
        let window = try #require(app.settingsWindow)
        defer { window.orderOut(nil) }
        let footer = window.footer
        #expect(footer.aboutButton.title == "About Hitoiki")
        #expect(footer.checkButton.title == "Check for Updates")
        #expect(footer.answerLine.title.isEmpty)
        // Pinned: not inside the form's scrolling area, and at the window's foot.
        #expect(footer.enclosingScrollView == nil)
        #expect(footer.superview === window.contentView)
        window.contentView?.layoutSubtreeIfNeeded()
        #expect(footer.frame.minY == 0)

        // Each button's own action, sent as a click sends it: `performClick` spins the run loop for its
        // highlight, and the test process ended there (ho-05.1).
        #expect(footer.aboutButton.sendAction(footer.aboutButton.action, to: footer.aboutButton.target))
        let about = try #require(app.aboutWindow)
        defer { about.orderOut(nil) }
        #expect(about.isVisible)
        #expect(about.title == "About Hitoiki")

        // With the switch off, the button checks.
        stand.hold()
        #expect(footer.checkButton.sendAction(footer.checkButton.action, to: footer.checkButton.target))
        try await until { stand.requests.count == 1 }
        #expect(footer.checkButton.title == "Checking…")
        stand.release()
        try await until { footer.answerLine.title == "Hitoiki is up to date." }
        #expect(footer.checkButton.title == "Check for Updates")
        #expect(stand.requests.count == 1)

        // The answer stays until the window closes.
        window.performClose(nil)
        #expect(footer.answerLine.title.isEmpty)
        app.showSettings(nil)
        #expect(footer.answerLine.title.isEmpty)
        #expect(suite.keys == ["updateCheckEnabled"])
    }

    @Test("Check for Updates… from the menu opens settings and answers in the footer: a newer release")
    internal func checkFromMenu() async throws {
        let suite = try ThrowawaySuite()
        defer { suite.remove() }
        let settings = Settings(defaults: suite.defaults)
        let scratch = ThrowawayHistory(following: settings)
        defer { scratch.remove() }
        let stand = FetchStandIn(tag: "v1.1")
        let check = UpdateCheck(version: "1.0.0", enabled: { settings.updateCheckEnabled }, fetch: stand.fetch)
        let app = HitoikiApp(settings: settings, history: scratch.history, updateCheck: check)
        #expect(app.settingsWindow == nil)
        app.checkForUpdates(nil)
        let window = try #require(app.settingsWindow)
        defer { window.orderOut(nil) }
        #expect(window.isVisible)
        try await until { window.footer.answerLine.title == "Hitoiki 1.1 is available." }
        #expect(stand.requests.count == 1)
        #expect(check.available == "1.1")
    }

    @Test("About is one window: shown twice, closed and shown again, it is the same window, and Escape closes it")
    internal func oneAbout() throws {
        let suite = try ThrowawaySuite()
        defer { suite.remove() }
        let settings = Settings(defaults: suite.defaults)
        let scratch = ThrowawayHistory(following: settings)
        defer { scratch.remove() }
        let app = HitoikiApp(settings: settings, history: scratch.history)
        app.showAbout(nil)
        let first = try #require(app.aboutWindow)
        defer { first.orderOut(nil) }
        #expect(first.isVisible)
        app.showAbout(nil)
        #expect(app.aboutWindow === first)
        first.performClose(nil)
        #expect(!first.isVisible)
        app.showAbout(nil)
        #expect(app.aboutWindow === first)
        #expect(NSApplication.shared.windows.filter { $0 is AboutWindow && $0.isVisible }.count == 1)
        first.sendEvent(try escape(in: first))
        #expect(!first.isVisible)
    }
}

/// The macros' nine boxes in the shown settings window, from the top, once the form has laid them out.
@MainActor
private func macroBoxes(in window: NSWindow) async throws -> [NSTextField] {
    func boxes() -> [NSTextField] {
        descendants(of: window.contentView).compactMap { $0 as? NSTextField }.filter(\.isEditable)
    }
    try await until { boxes().count == Settings.macroSlots }
    // Window coordinates rise upward: the first row is the highest.
    return boxes().sorted { $0.convert($0.bounds, to: nil).minY > $1.convert($1.bounds, to: nil).minY }
}

/// Every view under `view`, depth first.
@MainActor
private func descendants(of view: NSView?) -> [NSView] {
    guard let view else { return [] }
    return view.subviews + view.subviews.flatMap { descendants(of: $0) }
}

/// The Escape key going down in `window`, as the keyboard sends it.
@MainActor
private func escape(modifiers: NSEvent.ModifierFlags = [], in window: NSWindow) throws -> NSEvent {
    try #require(
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            isARepeat: false,
            keyCode: UInt16(kVK_Escape)))
}

/// What a followed effect was applied with, in order.
@MainActor
private final class Seen {
    var values: [Appearance] = []
}

/// A key going down in `window`, as the keyboard sends it.
@MainActor
private func keyDown(
    _ characters: String, code: Int, modifiers: NSEvent.ModifierFlags, in window: NSWindow
) throws -> NSEvent {
    try #require(
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: UInt16(code)))
}

/// Stands in for the application: takes the terminate and showSettings selectors and records who sent each,
/// ending nothing and opening nothing.
@MainActor
private final class Terminations: NSResponder {
    var senders: [Any?] = []
    var settings: [Any?] = []

    @objc
    func terminate(_ sender: Any?) {
        senders.append(sender)
    }

    @objc
    func showSettings(_ sender: Any?) {
        settings.append(sender)
    }
}
