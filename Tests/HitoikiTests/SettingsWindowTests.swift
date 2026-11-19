// The settings-window suite and its window helpers, in one file, which runs past the length rule rather than
// split the suite (ho-06.2 Decision 11).
// swiftlint:disable file_length

import AppKit
import Carbon.HIToolbox
import Foundation
import Testing

@testable import Hitoiki

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

        // Command-Q from settings, no new key in the defaults, the macro rows' spacing.

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

        @Test("History, settings, About and a manual check leave the defaults with the eleven settings keys alone")
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
            let stand = try FetchStandIn(tag: "v1.1")
            let check = UpdateCheck(version: "1.0.0", enabled: { settings.updateCheckEnabled }, fetch: stand.fetch)
            let app = HitoikiApp(settings: settings, history: history, updateCheck: check)
            app.showSettings(nil)
            app.checkForUpdates(nil)
            try await until { check.answer == .available("1.1") }
            app.showAbout(nil)
            app.aboutWindow?.orderOut(nil)
            app.settingsWindow?.orderOut(nil)
            #expect(suite.keys == settingsKeys)
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
            // 32 points apart, a 5-point gap between the 27-point boxes.
            #expect(abs(pitches[0] - 32) < 0.5)
            #expect(frames.allSatisfy { abs($0.height - 27) < 0.5 })
        }

        // Command-N goes to its macro's box; Command-comma does nothing here (ho-05.2 Decisions 14 and 15, from
        // the run sheet).

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

// The footer, Check for Updates… from the menu, and the one About window; in the settings-window suite, which
// runs inside the Panel suite, one test at a time.
extension PanelTests.SettingsWindowTests {
    @Test("The footer is the two buttons alone, outside the scrolling form; About shows About; Check checks")
    internal func footer() async throws {
        let suite = try ThrowawaySuite()
        defer { suite.remove() }
        let settings = Settings(defaults: suite.defaults)
        settings.updateCheckEnabled = false
        let scratch = ThrowawayHistory(following: settings)
        defer { scratch.remove() }
        let stand = try FetchStandIn(tag: "v1.0.0")
        let check = UpdateCheck(version: "1.0.0", enabled: { settings.updateCheckEnabled }, fetch: stand.fetch)
        let app = HitoikiApp(settings: settings, history: scratch.history, updateCheck: check)
        app.showSettings(nil)
        let window = try #require(app.settingsWindow)
        defer { window.orderOut(nil) }
        let footer = window.footer
        #expect(footer.aboutButton.title == "About Hitoiki")
        #expect(footer.checkButton.title == "Check for Updates")
        // The two buttons and nothing else, no answer line.
        let buttons = descendants(of: footer).compactMap { $0 as? NSButton }
        #expect(buttons.map(\.title) == ["About Hitoiki", "Check for Updates"])
        #expect(!descendants(of: footer).contains { $0 is NSTextField })
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
        try await until { check.answer == .upToDate }
        #expect(footer.checkButton.title == "Check for Updates")
        #expect(stand.requests.count == 1)

        // The answer, shown in the form, stays until the window closes.
        window.performClose(nil)
        #expect(check.answer == nil)
        app.showSettings(nil)
        #expect(check.answer == nil)
        #expect(suite.keys == ["updateCheckEnabled"])
    }

    @Test("Check for Updates… from the menu opens settings and runs a manual check there: a newer release")
    internal func checkFromMenu() async throws {
        let suite = try ThrowawaySuite()
        defer { suite.remove() }
        let settings = Settings(defaults: suite.defaults)
        let scratch = ThrowawayHistory(following: settings)
        defer { scratch.remove() }
        let stand = try FetchStandIn(tag: "v1.1")
        let check = UpdateCheck(version: "1.0.0", enabled: { settings.updateCheckEnabled }, fetch: stand.fetch)
        let app = HitoikiApp(settings: settings, history: scratch.history, updateCheck: check)
        #expect(app.settingsWindow == nil)
        app.checkForUpdates(nil)
        let window = try #require(app.settingsWindow)
        defer { window.orderOut(nil) }
        #expect(window.isVisible)
        try await until { check.answer == .available("1.1") }
        #expect(stand.requests.count == 1)
        #expect(check.available == "1.1")
    }

    // The answer's lifetime: the answer line shows the answer of a manual check started since the window was last
    // shown, and nothing else. Each reply is held by the stand-in until the test releases it (ho-06.1 Decision 17,
    // as restated by ho-06.1.1).

    @Test("Answer lifetime, partitions 1 and 5: the reply arrives with the window open and shows; closing takes it")
    internal func answerWhileOpen() async throws {
        let suite = try ThrowawaySuite()
        defer { suite.remove() }
        let settings = Settings(defaults: suite.defaults)
        let scratch = ThrowawayHistory(following: settings)
        defer { scratch.remove() }
        let stand = try FetchStandIn(tag: "v1.1")
        let check = UpdateCheck(version: "1.0.0", enabled: { false }, fetch: stand.fetch)
        let app = HitoikiApp(settings: settings, history: scratch.history, updateCheck: check)
        app.showSettings(nil)
        let window = try #require(app.settingsWindow)
        defer { window.orderOut(nil) }

        stand.hold()
        try await startManualCheck(in: window, held: stand)
        #expect(check.answer == nil)
        stand.release()
        try await until { !check.checking }
        // Partition 1.
        #expect(check.answer == .available("1.1"))

        // Partition 5.
        window.performClose(nil)
        #expect(!window.isVisible)
        #expect(check.answer == nil)
        app.showSettings(nil)
        #expect(check.answer == nil)
        #expect(stand.requests.count == 1)
    }

    @Test("Answer lifetime, partition 2: the window closes, then the reply arrives; no answer, now or when shown again")
    internal func replyWhileClosed() async throws {
        let suite = try ThrowawaySuite()
        defer { suite.remove() }
        let settings = Settings(defaults: suite.defaults)
        let scratch = ThrowawayHistory(following: settings)
        defer { scratch.remove() }
        let stand = try FetchStandIn(tag: "v1.1")
        let check = UpdateCheck(version: "1.0.0", enabled: { false }, fetch: stand.fetch)
        let app = HitoikiApp(settings: settings, history: scratch.history, updateCheck: check)
        app.showSettings(nil)
        let window = try #require(app.settingsWindow)
        defer { window.orderOut(nil) }

        stand.hold()
        try await startManualCheck(in: window, held: stand)
        window.performClose(nil)
        #expect(!window.isVisible)
        stand.release()
        try await until { !check.checking }
        #expect(check.answer == nil)
        // The panel's update line is not the window's: the newer release still sets it.
        #expect(check.available == "1.1")

        app.showSettings(nil)
        #expect(window.isVisible)
        #expect(check.answer == nil)
        #expect(stand.requests.count == 1)
    }

    @Test("Answer lifetime, partition 3: closed and shown again, then the old reply arrives; no answer")
    internal func oldReplyAfterReopen() async throws {
        let suite = try ThrowawaySuite()
        defer { suite.remove() }
        let settings = Settings(defaults: suite.defaults)
        let scratch = ThrowawayHistory(following: settings)
        defer { scratch.remove() }
        let stand = try FetchStandIn(tag: "v1.1")
        let check = UpdateCheck(version: "1.0.0", enabled: { false }, fetch: stand.fetch)
        let app = HitoikiApp(settings: settings, history: scratch.history, updateCheck: check)
        app.showSettings(nil)
        let window = try #require(app.settingsWindow)
        defer { window.orderOut(nil) }

        stand.hold()
        try await startManualCheck(in: window, held: stand)
        window.performClose(nil)
        app.showSettings(nil)
        #expect(window.isVisible)
        stand.release()
        try await until { !check.checking }
        #expect(check.answer == nil)
        #expect(check.available == "1.1")
        #expect(stand.requests.count == 1)
    }

    @Test("Answer lifetime, partition 4: after partition 3, a new check's reply shows its own answer")
    internal func newCheckAfterOldReply() async throws {
        let suite = try ThrowawaySuite()
        defer { suite.remove() }
        let settings = Settings(defaults: suite.defaults)
        let scratch = ThrowawayHistory(following: settings)
        defer { scratch.remove() }
        // The old check finds 1.2; the new one, an equal tag. "Up to date" can only be the new check's answer.
        let stand = try FetchStandIn(tag: "v1.2")
        let check = UpdateCheck(version: "1.0.0", enabled: { false }, fetch: stand.fetch)
        let app = HitoikiApp(settings: settings, history: scratch.history, updateCheck: check)
        app.showSettings(nil)
        let window = try #require(app.settingsWindow)
        defer { window.orderOut(nil) }

        // Partition 3.
        stand.hold()
        try await startManualCheck(in: window, held: stand)
        window.performClose(nil)
        app.showSettings(nil)
        stand.release()
        try await until { !check.checking }
        #expect(check.answer == nil)
        #expect(check.available == "1.2")

        // The new check, started in this opening.
        stand.reply = try .success((FetchStandIn.body(tag: "v1.0.0"), FetchStandIn.response()))
        stand.hold()
        try await startManualCheck(in: window, held: stand)
        #expect(check.answer == nil)
        stand.release()
        try await until { !check.checking }
        #expect(check.answer == .upToDate)
        #expect(check.available == "1.2")
        #expect(stand.requests.count == 2)
    }

    @Test("Open at Login is read from the system each time settings is shown; nothing is written to the defaults")
    internal func loginItemReadOnShow() throws {
        let suite = try ThrowawaySuite()
        defer { suite.remove() }
        let settings = Settings(defaults: suite.defaults)
        let scratch = ThrowawayHistory(following: settings)
        defer { scratch.remove() }
        let stand = LoginServiceStandIn()
        let item = LoginItem(bundleIdentifier: "com.sageframe.hitoiki", service: stand.service)
        let app = HitoikiApp(settings: settings, history: scratch.history, loginItem: item)
        app.showSettings(nil)
        let window = try #require(app.settingsWindow)
        defer { window.orderOut(nil) }
        #expect(stand.reads == 1)
        #expect(!item.isOn)

        // Turned on in System Settings › General › Login Items while settings was closed.
        window.performClose(nil)
        stand.state = .enabled
        app.showSettings(nil)
        #expect(stand.reads == 2)
        #expect(item.isOn)
        #expect(stand.registers == 0 && stand.unregisters == 0)
        #expect(suite.keys.isEmpty)
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

/// Presses the footer's Check for Updates as a click does, and waits for the request to reach the stand-in.
///
/// The stand-in holds the request there until the test releases it.
@MainActor
private func startManualCheck(in window: SettingsWindow, held stand: FetchStandIn) async throws {
    let sent = stand.requests.count
    let button = window.footer.checkButton
    #expect(button.sendAction(button.action, to: button.target))
    try await until { stand.requests.count == sent + 1 }
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
