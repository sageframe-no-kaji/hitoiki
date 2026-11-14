// The settings the panel reads at use, its keys for settings and quitting, and settings opened from it. One
// area in one file, which runs past the length rule rather than split the area (ho-06.2 Decision 11).
// swiftlint:disable file_length

import AppKit
import Carbon.HIToolbox
import Darwin
import Foundation
import HitoikiCore
import Testing

@testable import Hitoiki

// Settings read at use: the directory at Return, the macros at Command-N, the terminal at Open in
// Terminal; the hotkey's notice; the gear and Command-Q.
extension PanelTests {
    @Test("The fixed folder is read at Return: a change between two commands moves the second")
    internal func directoryReadAtReturn() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let first = fixture.home + "/first-" + UUID().uuidString
        let second = fixture.home + "/second-" + UUID().uuidString
        for folder in [first, second] {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: false)
        }
        fixture.settings.directoryPath = first
        fixture.panel.submit("pwd")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        // `pwd` prints the physical path; the temporary directory sits behind a symbolic link.
        #expect(fixture.window.transcript.string.hasSuffix("/" + URL(fileURLWithPath: first).lastPathComponent + "\n"))
        #expect(fixture.window.status.stringValue == "exit 0")

        fixture.settings.directoryPath = second
        fixture.panel.submit("pwd")
        try await fixture.until { fixture.window.transcript.string.contains("second-") }
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(fixture.window.transcript.string.hasSuffix("/" + URL(fileURLWithPath: second).lastPathComponent + "\n"))

        fixture.settings.directoryMode = .home
        fixture.panel.submit("pwd")
        try await fixture.until { !fixture.window.transcript.string.contains("second-") }
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(fixture.window.transcript.string == FileManager.default.homeDirectoryForCurrentUser.path + "\n")
    }

    @Test(
        "A fixed folder that is gone: the command runs in home, the strip says so from Running to Done, the next checks again"
    )
    internal func missingFolder() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let folder = fixture.home + "/gone-" + UUID().uuidString
        fixture.settings.directoryPath = folder
        let window = fixture.window
        fixture.panel.show()
        fixture.panel.submit("echo ready; read -r line; pwd")
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        let said = "\(folder) could not be found; ran in home"
        #expect(window.status.stringValue.hasPrefix(said))
        #expect(same(window.status.textColor, Theme.Token.alarm))

        fixture.panel.keystroke(.write([0x0D]))
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(window.transcript.string.hasSuffix("\n" + home + "\n"))
        #expect(window.status.stringValue == said + " · exit 0")
        #expect(same(window.status.textColor, Theme.Token.alarm))
        fixture.clickOut()
        fixture.panel.toggle()
        #expect(window.status.stringValue == said + " · exit 0")

        // The folder back: the next command finds it, and the strip is the command's own.
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: false)
        fixture.panel.submit("pwd")
        try await fixture.until { window.transcript.string.contains("gone-") }
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(window.transcript.string.hasSuffix("/" + URL(fileURLWithPath: folder).lastPathComponent + "\n"))
        #expect(window.status.stringValue == "exit 0")
        #expect(same(window.status.textColor, Theme.Token.inkFaint))
    }

    @Test("A fixed folder that is a file, not a folder, is gone too")
    internal func folderIsAFile() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let file = fixture.home + "/a-file"
        try "".write(toFile: file, atomically: true, encoding: .utf8)
        fixture.settings.directoryPath = file
        fixture.panel.submit("pwd")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(fixture.window.transcript.string == FileManager.default.homeDirectoryForCurrentUser.path + "\n")
        #expect(fixture.window.status.stringValue.hasPrefix("\(file) could not be found"))
    }

    @Test("Command-1 in Composing loads slot 1 into the input, the cursor at its end, and runs nothing")
    internal func macroLoads() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let command = "touch macro-ran; echo macro"
        fixture.settings.macros = [command]
        let window = fixture.window
        fixture.panel.show()
        let before = fixture.look()
        press(try commandDigit(1, in: window), in: window)
        #expect(window.input.stringValue == command)
        let editor = try #require(window.input.currentEditor())
        #expect(window.firstResponder === editor)
        #expect(editor.selectedRange == NSRange(location: (command as NSString).length, length: 0))
        let after = fixture.look()
        #expect(after.input == command)
        #expect(after.with(input: before.input) == before)
        #expect(fixture.panel.state == nil)
        #expect(!fixture.panel.isBusy)
        #expect(window.outputCard.isHidden)
        #expect(try await children().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.home + "/macro-ran"))
    }

    @Test(
        "Command-N replaces typed text; an empty slot leaves the input as it was; a slot changed in settings loads the change"
    )
    internal func macroReplaces() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        var macros = fixture.settings.macros
        macros[2] = "uptime"
        fixture.settings.macros = macros
        let window = fixture.window
        fixture.panel.show()
        window.input.stringValue = "typed line"
        press(try commandDigit(3, in: window), in: window)
        #expect(window.input.stringValue == "uptime")
        press(try commandDigit(2, in: window), in: window)
        #expect(window.input.stringValue == "uptime")
        press(try commandDigit(9, in: window), in: window)
        #expect(window.input.stringValue == "uptime")

        macros[2] = "df -h"
        fixture.settings.macros = macros
        press(try commandDigit(3, in: window), in: window)
        #expect(window.input.stringValue == "df -h")
        #expect(fixture.panel.state == nil)
    }

    @Test("In Done, Command-1 loads and changes nothing else; Return then runs the macro's command")
    internal func macroInDone() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.settings.macros = ["echo from-the-macro"]
        let window = fixture.window
        fixture.panel.show()
        fixture.panel.submit("echo shown; exit 3")
        #expect(try await fixture.done() == .done(.status(3), retry: nil))
        let before = fixture.look()
        press(try commandDigit(1, in: window), in: window)
        let after = fixture.look()
        #expect(after.input == "echo from-the-macro")
        #expect(after.with(input: before.input) == before)

        let editor = try #require(window.input.currentEditor())
        editor.keyDown(with: try key("\r", code: UInt16(kVK_Return), in: window))
        try await fixture.transcriptContains("from-the-macro")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(window.transcript.string == "from-the-macro\n")
    }

    @Test("While Running, Command-1 changes nothing and the command reads nothing")
    internal func macroWhileRunning() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.settings.macros = ["echo never"]
        let window = fixture.window
        fixture.panel.show()
        fixture.panel.submit("echo ready; read -r secret; printf %s \"${#secret}\" > length")
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        #expect(window.firstResponder === window.transcript)
        let before = fixture.look()
        press(try commandDigit(1, in: window), in: window)
        #expect(fixture.look() == before)
        #expect(window.input.stringValue.isEmpty)
        fixture.panel.keystroke(.write([0x0D]))
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(try String(contentsOfFile: fixture.home + "/length", encoding: .utf8) == "0")
        #expect(window.input.stringValue.isEmpty)
    }

    // The four modifier keys decide the macro route, and nothing else the event carries (ho-05.1.1).

    @Test("Caps Lock on, in Composing: Command-1 loads slot 1 over the typed text and runs nothing")
    internal func macroLoadsWithCapsLock() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let command = "touch macro-ran; echo macro"
        fixture.settings.macros = [command]
        let window = fixture.window
        fixture.panel.show()
        window.input.stringValue = "typed line"
        let before = fixture.look()
        press(try commandDigit(1, with: [.command, .capsLock], in: window), in: window)
        let after = fixture.look()
        #expect(after.input == command)
        #expect(after.with(input: before.input) == before)
        #expect(fixture.panel.state == nil)
        #expect(try await children().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.home + "/macro-ran"))
    }

    @Test("Caps Lock on, in Done: Command-1 loads and changes nothing else")
    internal func macroInDoneWithCapsLock() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.settings.macros = ["echo from-the-macro"]
        let window = fixture.window
        fixture.panel.show()
        fixture.panel.submit("echo shown; exit 3")
        #expect(try await fixture.done() == .done(.status(3), retry: nil))
        let before = fixture.look()
        press(try commandDigit(1, with: [.command, .capsLock], in: window), in: window)
        let after = fixture.look()
        #expect(after.input == "echo from-the-macro")
        #expect(after.with(input: before.input) == before)
    }

    @Test("Caps Lock on, while Running: Command-1 changes nothing and the command reads nothing")
    internal func macroWhileRunningWithCapsLock() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.settings.macros = ["echo never"]
        let window = fixture.window
        fixture.panel.show()
        fixture.panel.submit("echo ready; read -r secret; printf %s \"${#secret}\" > length")
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        let before = fixture.look()
        press(try commandDigit(1, with: [.command, .capsLock], in: window), in: window)
        #expect(fixture.look() == before)
        fixture.panel.keystroke(.write([0x0D]))
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(try String(contentsOfFile: fixture.home + "/length", encoding: .utf8) == "0")
        #expect(window.input.stringValue.isEmpty)
    }

    @Test("Option-Command-1 is not a macro: the typed text stays and nothing runs")
    internal func optionCommandDigitIsNotAMacro() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.settings.macros = ["echo never"]
        let window = fixture.window
        fixture.panel.show()
        window.input.stringValue = "typed line"
        let before = fixture.look()
        press(try commandDigit(1, with: [.option, .command], in: window), in: window)
        #expect(fixture.look() == before)
        #expect(window.input.stringValue == "typed line")
        #expect(fixture.panel.state == nil)
        #expect(try await children().isEmpty)
    }

    @Test(
        "Open in Terminal with a terminal that is not installed: the strip says so through hide and show, until the next submission or a clear"
    )
    internal func terminalMissing() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.settings.terminal = "org.example.no-such-terminal"
        let window = fixture.window
        fixture.panel.show()
        fixture.panel.submit("echo shown")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(!window.openButton.isHidden)
        // The button's own action, sent as a click sends it: `performClick` spins the run loop for its
        // highlight, and the next await then found the main run loop ended and the test process exited 0.
        #expect(window.openButton.sendAction(window.openButton.action, to: window.openButton.target))
        let said = "org.example.no-such-terminal could not be found."
        #expect(window.status.stringValue == said)
        #expect(same(window.status.textColor, Theme.Token.alarm))
        let before = fixture.look()
        fixture.clickOut()
        #expect(fixture.look() == before.hidden)
        fixture.panel.toggle()
        #expect(fixture.look() == before)
        #expect(same(window.status.textColor, Theme.Token.alarm))

        // The next submission takes it away.
        fixture.panel.submit("echo again")
        try await fixture.transcriptContains("again")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(window.status.stringValue == "exit 0")
        #expect(same(window.status.textColor, Theme.Token.inkFaint))

        // So does a clear.
        fixture.panel.openInTerminal()
        #expect(window.status.stringValue == said)
        fixture.panel.escape()
        #expect(fixture.look() == .clean)
        #expect(window.status.stringValue.isEmpty)
    }

    @Test("The hotkey's notice and the settings line name the registered combination, not a constant")
    internal func hotkeyNamed() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let combination = Shortcut.Combination(
            keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(controlKey | optionKey | cmdKey))
        #expect(Hotkey.register(keyCode: combination.keyCode, modifiers: combination.modifiers) {} == noErr)
        defer { Hotkey.unregister() }
        #expect(Hotkey.settingsLine(launch: noErr, attempted: Settings.defaultShortcut) == "⌃⌥⌘J is registered.")

        let status = Hotkey.replace(keyCode: combination.keyCode, modifiers: combination.modifiers)
        let notice = try #require(Hotkey.statusText(for: status, combination: combination))
        fixture.panel.note(notice)
        #expect(fixture.window.notice.stringValue.hasPrefix("⌃⌥⌘J is unavailable (\(eventHotKeyExistsErr))."))
        #expect(!fixture.window.notice.stringValue.contains("Space"))

        // Nothing registered: settings says why the launch's failed, naming what it tried.
        Hotkey.unregister()
        #expect(
            Hotkey.settingsLine(launch: status, attempted: combination)
                == Hotkey.statusText(for: status, combination: combination))
    }

    @Test("The gear has no menu: a click sends showSettings up the responder chain to the application's delegate")
    internal func gearOpensSettings() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let row = try #require(fixture.window.input.superview as? NSStackView)
        let gear = try #require(row.arrangedSubviews.last as? NSButton)
        #expect(gear.action == #selector(HitoikiApp.showSettings(_:)))
        // No target: the action climbs the responder chain to the application's delegate.
        #expect(gear.target == nil)
        #expect(gear.menu == nil)

        // The application's delegate answers it. That it opens the one settings window is `oneWindow`'s to
        // witness, in the settings-window suite.
        #expect(HitoikiApp.instancesRespond(to: gear.action))
    }

    @Test("Command-Q sends the terminate selector to the application, in Composing, with text typed, and while Running")
    internal func commandQuit() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let window = fixture.window
        // Unless a test stands in for it, the selector goes to the application itself.
        #expect(window.application === NSApplication.shared)
        let quit = QuitRecorder()
        window.application = quit
        fixture.panel.show()
        let commandQ = try key("q", code: UInt16(kVK_ANSI_Q), modifiers: .command, in: window)

        let clean = fixture.look()
        press(commandQ, in: window)
        #expect(quit.senders.count == 1)
        #expect((quit.senders.last as? PanelWindow) === window)
        #expect(fixture.look() == clean)

        window.input.stringValue = "typed line"
        let typed = fixture.look()
        press(commandQ, in: window)
        #expect(quit.senders.count == 2)
        #expect(fixture.look() == typed)
        #expect(window.input.stringValue == "typed line")

        // Caps Lock on: still Command-Q.
        press(try key("Q", code: UInt16(kVK_ANSI_Q), modifiers: [.command, .capsLock], in: window), in: window)
        #expect(quit.senders.count == 3)

        // Option-Command-Q is not it.
        window.input.stringValue = ""
        press(try key("q", code: UInt16(kVK_ANSI_Q), modifiers: [.command, .option], in: window), in: window)
        #expect(quit.senders.count == 3)

        fixture.panel.submit("echo ready; read -r line")
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        press(commandQ, in: window)
        #expect(quit.senders.count == 4)
        #expect(fixture.panel.isBusy)
        fixture.panel.keystroke(.write([0x0D]))
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
    }
}

/// Stands in for the application: takes the terminate selector and records who sent it, ending nothing.
@MainActor
private final class QuitRecorder: NSResponder {
    var senders: [Any?] = []

    @objc
    func terminate(_ sender: Any?) {
        senders.append(sender)
    }
}

// Command-comma: Settings from the panel in every state, by the gear's route (ho-05.2 Decision 15, from the
// run sheet).
extension PanelTests {
    @Test("Command-comma sends the gear's showSettings with no target, up the panel's responder chain, in every state")
    internal func commandComma() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let window = fixture.window
        // The stand-in ends the panel's responder chain: only an action sent with no target, climbing the key
        // window's chain as the gear's click does, reaches it. The application seam gets a decoy that must stay
        // empty, so a route through it fails here.
        let opener = SettingsOpener()
        let decoy = SettingsOpener()
        window.nextResponder = opener
        window.application = decoy
        let row = try #require(window.input.superview as? NSStackView)
        let gear = try #require(row.arrangedSubviews.last as? NSButton)
        fixture.panel.show()
        let comma = try key(",", code: UInt16(kVK_ANSI_Comma), modifiers: .command, in: window)
        let capsComma = try key(",", code: UInt16(kVK_ANSI_Comma), modifiers: [.command, .capsLock], in: window)

        let clean = fixture.look()
        press(comma, in: window)
        #expect(opener.senders.count == 1)
        // Sent by the gear itself, as its click sends it.
        #expect((opener.senders.last as? NSButton) === gear)
        #expect(gear.target == nil && gear.action == #selector(HitoikiApp.showSettings(_:)))
        #expect(fixture.look() == clean)

        window.input.stringValue = "typed line"
        let typed = fixture.look()
        press(capsComma, in: window)
        #expect(opener.senders.count == 2)
        #expect(fixture.look() == typed)

        // Option-Command-comma is not it.
        press(try key(",", code: UInt16(kVK_ANSI_Comma), modifiers: [.command, .option], in: window), in: window)
        #expect(opener.senders.count == 2)

        fixture.panel.submit("echo shown")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        let done = fixture.look()
        press(comma, in: window)
        #expect(opener.senders.count == 3)
        #expect(fixture.look() == done)

        fixture.panel.submit("echo ready; read -r line; printf %s \"${#line}\" > length")
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        press(capsComma, in: window)
        #expect(opener.senders.count == 4)
        #expect(fixture.panel.isBusy)
        // The command read nothing of the key.
        fixture.panel.keystroke(.write([0x0D]))
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(try String(contentsOfFile: fixture.home + "/length", encoding: .utf8) == "0")
        #expect(opener.terminations == 0)
        #expect(decoy.senders.isEmpty && decoy.terminations == 0)
        #expect(opener.senders.allSatisfy { ($0 as? NSButton) === gear })
    }
}

/// Stands in for the application's delegate: takes the gear's showSettings selector and records who sent it,
/// opening nothing; a terminate is counted, so a wrong route shows.
@MainActor
private final class SettingsOpener: NSResponder {
    var senders: [Any?] = []
    var terminations = 0

    @objc
    func showSettings(_ sender: Any?) {
        senders.append(sender)
    }

    @objc
    func terminate(_ sender: Any?) {
        terminations += 1
    }
}

// Settings opened from the panel returns to it: from the gear and from Command-comma the panel hides as at a
// click-out, and closing settings, by Escape or by the close button, shows it as it was; from the menu, with the
// panel not up, closing shows nothing.
extension PanelTests {
    @Test("From the gear: settings hides the panel; Command-Q there still quits; Escape brings the panel back")
    internal func settingsFromGearReturns() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let app = HitoikiApp(settings: fixture.settings, history: fixture.history)
        fixture.panel.show()
        fixture.window.input.stringValue = "typed line"
        let before = fixture.look()
        // The click's own delivery, the gear as sender up the responder chain, is gearOpensSettings's to witness.
        app.showSettings(try gearButton(fixture))
        let settings = try #require(app.settingsWindow)
        defer { settings.orderOut(nil) }
        #expect(settings.isVisible)
        #expect(!fixture.window.isVisible)

        // Command-Q from settings still quits, and shows nothing.
        let quit = QuitRecorder()
        settings.application = quit
        press(try key("q", code: UInt16(kVK_ANSI_Q), modifiers: .command, in: settings), in: settings)
        #expect(quit.senders.count == 1)
        #expect(settings.isVisible)
        #expect(!fixture.window.isVisible)

        settings.sendEvent(try key("\u{1B}", code: UInt16(kVK_Escape), in: settings))
        #expect(!settings.isVisible)
        #expect(fixture.look() == before)
        #expect(fixture.look().input == "typed line")
        #expect(fixture.keyboardInInput)
    }

    @Test("From Command-comma, in Done: the close button closes settings; the panel returns with state and transcript")
    internal func settingsFromCommandCommaReturns() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let app = HitoikiApp(settings: fixture.settings, history: fixture.history)
        // The delegate at the end of the panel's responder chain, as the application holds it in the app.
        let forward = SettingsForwarder(app)
        fixture.window.nextResponder = forward
        fixture.panel.show()
        fixture.panel.submit("echo shown; exit 3")
        #expect(try await fixture.done() == .done(.status(3), retry: nil))
        try await fixture.transcriptContains("shown")
        let before = fixture.look()

        press(try key(",", code: UInt16(kVK_ANSI_Comma), modifiers: .command, in: fixture.window), in: fixture.window)
        #expect(forward.senders.count == 1)
        let settings = try #require(app.settingsWindow)
        defer { settings.orderOut(nil) }
        #expect(settings.isVisible)
        #expect(!fixture.window.isVisible)

        let close = try #require(settings.standardWindowButton(.closeButton))
        #expect(close.sendAction(close.action, to: close.target))
        #expect(!settings.isVisible)
        #expect(fixture.look() == before)
        #expect(fixture.panel.state == .done(.status(3), retry: nil))
        #expect(fixture.window.transcript.string.contains("shown"))
        #expect(fixture.keyboardInInput)
    }

    @Test("From the menu, the panel not up: Settings… and Check for Updates… close and show nothing")
    internal func settingsFromMenuShowsNothing() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let app = HitoikiApp(settings: fixture.settings, history: fixture.history)
        fixture.panel.show()
        fixture.window.input.stringValue = "typed line"
        // A click-out took it down.
        fixture.panel.hide()
        let hidden = fixture.look()
        #expect(!hidden.visible)
        let menu = MenuBarItem {}.menu
        let settingsItem = menu.items[4]
        let checkItem = menu.items[3]
        #expect(settingsItem.title == "Settings…" && checkItem.title == "Check for Updates…")

        app.showSettings(settingsItem)
        let settings = try #require(app.settingsWindow)
        defer { settings.orderOut(nil) }
        #expect(settings.isVisible)
        settings.sendEvent(try key("\u{1B}", code: UInt16(kVK_Escape), in: settings))
        #expect(!settings.isVisible)
        #expect(fixture.look() == hidden)

        app.checkForUpdates(checkItem)
        #expect(settings.isVisible)
        let close = try #require(settings.standardWindowButton(.closeButton))
        #expect(close.sendAction(close.action, to: close.target))
        #expect(!settings.isVisible)
        #expect(fixture.look() == hidden)
    }

    @Test("Opened from the gear, then brought forward from the menu while open: closing still returns to the panel")
    internal func settingsFromGearThenMenuReturns() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let app = HitoikiApp(settings: fixture.settings, history: fixture.history)
        fixture.panel.show()
        let before = fixture.look()
        app.showSettings(try gearButton(fixture))
        let settings = try #require(app.settingsWindow)
        defer { settings.orderOut(nil) }
        app.showSettings(MenuBarItem {}.menu.items[4])
        #expect(settings.isVisible)
        #expect(!fixture.window.isVisible)
        settings.sendEvent(try key("\u{1B}", code: UInt16(kVK_Escape), in: settings))
        #expect(fixture.look() == before)
    }
}

/// The gear at the bar's trailing edge.
@MainActor
private func gearButton(_ fixture: Fixture) throws -> NSButton {
    let row = try #require(fixture.window.input.superview as? NSStackView)
    return try #require(row.arrangedSubviews.last as? NSButton)
}

/// Stands where the application's delegate is in the app: takes the gear's showSettings from the panel's
/// responder chain, records who sent it, and hands it to `app`.
@MainActor
private final class SettingsForwarder: NSResponder {
    let app: HitoikiApp
    var senders: [Any?] = []

    init(_ app: HitoikiApp) {
        self.app = app
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    @objc
    func showSettings(_ sender: Any?) {
        senders.append(sender)
        app.showSettings(sender)
    }
}
