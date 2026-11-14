import AppKit
import Carbon.HIToolbox
import Darwin
import Foundation
import HitoikiCore
import Testing

@testable import Hitoiki

/// The input's field editor, which holds the keyboard while the input does.
@MainActor
private func fieldEditor(_ fixture: Fixture) throws -> NSTextView {
    try #require(fixture.window.input.currentEditor() as? NSTextView)
}

/// Types `text` into the input a key at a time, as the keyboard does.
@MainActor
private func type(_ text: String, in fixture: Fixture) throws {
    let editor = try fieldEditor(fixture)
    for character in text {
        editor.keyDown(with: try key(String(character), code: 0, in: fixture.window))
    }
}

/// A key the recall tests press in the input.
private enum InputKey {
    case up
    case down
    case left
    case right
    case enter
    case escape

    /// The characters the keyboard sends: AppKit's function-key characters for the arrows.
    var characters: String {
        switch self {
        case .up:
            "\u{F700}"
        case .down:
            "\u{F701}"
        case .left:
            "\u{F702}"
        case .right:
            "\u{F703}"
        case .enter:
            "\r"
        case .escape:
            "\u{1B}"
        }
    }

    /// The virtual key code.
    var code: Int {
        switch self {
        case .up:
            kVK_UpArrow
        case .down:
            kVK_DownArrow
        case .left:
            kVK_LeftArrow
        case .right:
            kVK_RightArrow
        case .enter:
            kVK_Return
        case .escape:
            kVK_Escape
        }
    }

    /// The arrows come with the numeric-pad and function flags, as from the keyboard.
    var modifiers: NSEvent.ModifierFlags {
        [.up, .down, .left, .right].contains(self) ? [.numericPad, .function] : []
    }
}

/// Presses `which` in the input's field editor, as the keyboard does.
@MainActor
private func tap(_ which: InputKey, in fixture: Fixture) throws {
    let event = try key(which.characters, code: UInt16(which.code), modifiers: which.modifiers, in: fixture.window)
    try fieldEditor(fixture).keyDown(with: event)
}

/// A letter with Command, as the keyboard sends it; with Caps Lock on, the letter comes as a capital.
@MainActor
private func commandKey(_ letter: String, code: Int, capsLock: Bool = false, in window: NSWindow) throws -> NSEvent {
    let modifiers: NSEvent.ModifierFlags = capsLock ? [.command, .capsLock] : .command
    return try key(capsLock ? letter.uppercased() : letter, code: UInt16(code), modifiers: modifiers, in: window)
}

/// The cursor is at the end of the input's text, with nothing selected.
@MainActor
private func cursorAtEnd(_ fixture: Fixture) throws -> Bool {
    let editor = try fieldEditor(fixture)
    return editor.selectedRange() == NSRange(location: (editor.string as NSString).length, length: 0)
}

// History's write moment: at Running, and at no other.
extension PanelTests {
    @Test("History on: a command is written at its Running; a start that fails before Running writes nothing")
    internal func writtenAtRunning() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.settings.historyEnabled = true
        fixture.panel.show()
        fixture.panel.submit("echo ready; read -r line")
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        // Still running, and the line is in the file.
        #expect(try fixture.historyText() == "echo ready; read -r line\n")
        fixture.panel.keystroke(.write([0x0D]))
        #expect(try await fixture.done() == .done(.status(0), retry: nil))

        fixture.window.input.stringValue = "echo never"
        try await failStart(fixture.window.input.stringValue, in: fixture)
        #expect(!fixture.panel.isBusy)
        #expect(fixture.window.status.stringValue.hasPrefix("Could not start: "))
        #expect(try fixture.historyText() == "echo ready; read -r line\n")
        #expect(fixture.history.entries == ["echo ready; read -r line"])
    }

    @Test("The -tt offer taken by a blank Return writes the ssh -tt line, after the ssh line that ran before it")
    internal func offerWritten() async throws {
        let fixture = try Fixture(homeOnPath: true)
        defer { fixture.tearDown() }
        try fixture.writeFakeSSH()
        fixture.settings.historyEnabled = true
        fixture.panel.show()
        fixture.panel.submit("ssh host 'sudo true'")
        #expect(try await fixture.done() == .done(.status(1), retry: "ssh -tt host 'sudo true'"))
        #expect(try fixture.historyText() == "ssh host 'sudo true'\n")
        #expect(fixture.window.input.stringValue.isEmpty)
        try tap(.enter, in: fixture)
        _ = try await fixture.running()
        try await fixture.transcriptContains("ok")
        #expect(try fixture.historyText() == "ssh host 'sudo true'\nssh -tt host 'sudo true'\n")
        fixture.panel.keystroke(.write([0x0D]))
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
    }

    @Test("History off: commands that run make no file; Down-arrow lists them from the session, once each")
    internal func sessionWithHistoryOff() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.panel.show()
        for line in ["echo one", "echo two", "echo one"] {
            try await fixture.ran(line)
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.historyFolder.path))
        try tap(.down, in: fixture)
        #expect(fixture.window.recall.rows == ["echo one", "echo two"])
    }
}

// The recall list.
extension PanelTests {
    @Test("Down-arrow on an empty input opens the list under the bar, top row selected; the input keeps the keyboard")
    internal func listOpens() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        for line in ["echo one", "echo two", "echo three"] {
            fixture.history.record(line)
        }
        fixture.panel.show()
        try tap(.down, in: fixture)
        let list = fixture.window.recall
        #expect(list.isOpen && list.isVisible)
        #expect(list.rows == ["echo three", "echo two", "echo one"])
        #expect(list.selected == 0)
        // Opening changed nothing on the panel, and the input still has the keyboard.
        #expect(fixture.look() == .clean)
        #expect(fixture.keyboardInInput)
        #expect(!list.canBecomeKey && !list.isKeyWindow)
        // A child of the panel, at the cards' width, its top below the bar card.
        let window = fixture.window
        let bar = window.convertToScreen(window.bar.convert(window.bar.bounds, to: nil))
        #expect(list.parent === window)
        #expect(list.frame.minX == bar.minX && list.frame.width == bar.width)
        #expect(list.frame.maxY < bar.minY)
        list.display()
    }

    @Test("Down opens at the top; Down, Down, Return puts the third entry in the input and runs nothing")
    internal func listChooses() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        for line in ["touch ran-1", "touch ran-2", "touch ran-3"] {
            fixture.history.record(line)
        }
        fixture.panel.show()
        for _ in 1...3 {
            try tap(.down, in: fixture)
        }
        #expect(fixture.window.recall.selected == 2)
        // Down at the last row stays there.
        try tap(.down, in: fixture)
        #expect(fixture.window.recall.selected == 2)
        try tap(.enter, in: fixture)
        #expect(!fixture.window.recall.isOpen)
        #expect(fixture.look() == Look.clean.with(input: "touch ran-1"))
        #expect(try cursorAtEnd(fixture))
        #expect(!fixture.panel.isBusy)
        #expect(try await children().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.home + "/ran-1"))

        try tap(.enter, in: fixture)
        try await fixture.until { !fixture.panel.isBusy }
        #expect(fixture.panel.state == .done(.status(0), retry: nil))
        #expect(FileManager.default.fileExists(atPath: fixture.home + "/ran-1"))
    }

    @Test("Up moves the selection newer; Up from the top row closes the list and leaves the input as it was")
    internal func upCloses() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        for line in ["echo one", "echo two", "echo three"] {
            fixture.history.record(line)
        }
        fixture.panel.show()
        try type("echo", in: fixture)
        try tap(.down, in: fixture)
        try tap(.down, in: fixture)
        #expect(fixture.window.recall.selected == 1)
        try tap(.up, in: fixture)
        #expect(fixture.window.recall.isOpen)
        #expect(fixture.window.recall.selected == 0)
        try tap(.up, in: fixture)
        #expect(!fixture.window.recall.isOpen)
        #expect(fixture.look() == Look.clean.with(input: "echo"))
    }

    @Test("Escape with the list open closes it and changes nothing else; the next Escape is the ladder's and clears")
    internal func escapeClosesList() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.history.record("echo one")
        fixture.panel.show()
        try type("echo", in: fixture)
        try tap(.down, in: fixture)
        #expect(fixture.window.recall.isOpen)
        let before = fixture.look()
        try tap(.escape, in: fixture)
        #expect(!fixture.window.recall.isOpen)
        #expect(fixture.look() == before)
        #expect(fixture.keyboardInInput)
        try tap(.escape, in: fixture)
        #expect(fixture.look() == .clean)
    }

    @Test("A two-line input: Down from the first line moves the cursor; from the last it opens the list on that line")
    internal func twoLines() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.history.record("echo one")
        fixture.history.record("ls -la")
        fixture.panel.show()
        fixture.window.input.stringValue = "first\nech"
        let editor = try fieldEditor(fixture)
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        try tap(.down, in: fixture)
        #expect(!fixture.window.recall.isOpen)
        // The cursor went down to the second line, which starts after "first\n".
        #expect(editor.selectedRange().location >= 6)

        editor.setSelectedRange(NSRange(location: 9, length: 0))
        try tap(.down, in: fixture)
        #expect(fixture.window.recall.rows == ["echo one"])
        try tap(.enter, in: fixture)
        #expect(fixture.window.input.stringValue == "first\necho one")
        #expect(try cursorAtEnd(fixture))
        #expect(fixture.panel.state == nil)
    }

    @Test("Typing with the list open narrows it, either case, and returns the selection to the top")
    internal func typingFilters() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        for line in ["ssh host-a uptime", "ping HOST-b", "ls"] {
            fixture.history.record(line)
        }
        fixture.panel.show()
        try tap(.down, in: fixture)
        try tap(.down, in: fixture)
        #expect(fixture.window.recall.rows.count == 3)
        #expect(fixture.window.recall.selected == 1)
        try type("host", in: fixture)
        #expect(fixture.window.recall.rows == ["ping HOST-b", "ssh host-a uptime"])
        #expect(fixture.window.recall.selected == 0)
        try tap(.down, in: fixture)
        try type("-a", in: fixture)
        #expect(fixture.window.recall.rows == ["ssh host-a uptime"])
        #expect(fixture.window.recall.selected == 0)
        #expect(fixture.window.input.stringValue == "host-a")
    }

    @Test("No commands yet, and No match: one faint row; Return closes the list, leaves the input and runs nothing")
    internal func emptyList() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let list = fixture.window.recall
        fixture.panel.show()
        try tap(.down, in: fixture)
        #expect(list.isOpen && list.rows.isEmpty)
        #expect(list.placeholder == "No commands yet")
        list.display()
        try tap(.enter, in: fixture)
        #expect(!list.isOpen)
        #expect(fixture.look() == .clean)

        fixture.history.record("echo one")
        try type("zzz", in: fixture)
        try tap(.down, in: fixture)
        #expect(list.isOpen && list.rows.isEmpty)
        #expect(list.placeholder == "No match")
        try tap(.enter, in: fixture)
        #expect(!list.isOpen)
        #expect(fixture.look() == Look.clean.with(input: "zzz"))
        #expect(try await children().isEmpty)
    }

    @Test("A click on a row loads it and closes the list; the panel is still the key window")
    internal func clickChooses() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        for line in ["echo one", "echo two", "echo three"] {
            fixture.history.record(line)
        }
        fixture.panel.show()
        try tap(.down, in: fixture)
        let list = fixture.window.recall
        let click = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: list.location(ofRow: 1),
                modifierFlags: [],
                timestamp: 0,
                windowNumber: list.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1))
        list.sendEvent(click)
        #expect(!list.isOpen)
        #expect(fixture.look() == Look.clean.with(input: "echo two"))
        #expect(fixture.keyboardInInput)
        #expect(!list.isKeyWindow)
    }

    @Test("A click-out or the hotkey hides the panel and closes the list; a start by Retry closes it too")
    internal func movingCloses() async throws {
        let fixture = try Fixture(homeOnPath: true)
        defer { fixture.tearDown() }
        try fixture.writeFakeSSH()
        fixture.history.record("echo one")
        let list = fixture.window.recall
        fixture.panel.show()
        try tap(.down, in: fixture)
        fixture.clickOut()
        #expect(!fixture.window.isVisible && !list.isOpen && !list.isVisible)
        fixture.panel.toggle()
        try tap(.down, in: fixture)
        #expect(list.isOpen)
        fixture.panel.toggle()
        #expect(!fixture.window.isVisible && !list.isOpen)

        fixture.panel.toggle()
        fixture.panel.submit("ssh host 'sudo true'")
        #expect(try await fixture.done() == .done(.status(1), retry: "ssh -tt host 'sudo true'"))
        try tap(.down, in: fixture)
        #expect(list.isOpen)
        let retry = fixture.window.retryButton
        #expect(retry.sendAction(retry.action, to: retry.target))
        #expect(!list.isOpen)
        _ = try await fixture.running()
        try await fixture.transcriptContains("ok")
        fixture.panel.keystroke(.write([0x0D]))
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
    }

    @Test("While a command runs, or a submission is in flight, Down-arrow opens nothing and the command reads nothing")
    internal func noListWhileBusy() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.history.record("echo one")
        let window = fixture.window
        fixture.panel.show()
        fixture.panel.submit("echo ready; read -r secret; printf %s \"${#secret}\" > length")
        _ = try await fixture.running()
        try await fixture.transcriptContains("ready")
        #expect(window.firstResponder === window.transcript)
        let down = try key("\u{F701}", code: UInt16(kVK_DownArrow), modifiers: [.numericPad, .function], in: window)
        press(down, in: window)
        #expect(!fixture.panel.down())
        #expect(!window.recall.isOpen)
        #expect(fixture.panel.suggestion == nil)
        fixture.panel.keystroke(.write([0x0D]))
        #expect(try await fixture.done() == .done(.status(0), retry: nil))
        #expect(try String(contentsOfFile: fixture.home + "/length", encoding: .utf8) == "0")

        let (inFlight, open) = try await reach(.inFlight)
        defer { inFlight.tearDown() }
        try tap(.down, in: inFlight)
        #expect(!inFlight.window.recall.isOpen)
        #expect(inFlight.panel.isBusy)
        try await inFlight.end(opening: open)
    }
}

// The grey suggestion.
extension PanelTests {
    @Test("Typing a prefix draws the rest of the newest entry in grey; the input's value is the typed text alone")
    internal func suggestionShown() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let saved = savePasteboard()
        defer { restorePasteboard(saved) }
        fixture.history.record("echo one")
        fixture.history.record("echo two")
        let window = fixture.window
        fixture.panel.show()
        try type("echo t", in: fixture)
        #expect(window.input.stringValue == "echo t")
        #expect(try fieldEditor(fixture).string == "echo t")
        #expect(fixture.panel.suggestion == "wo")
        #expect(window.shownSuggestion == "wo")
        // Command-A and Command-C take the typed text and nothing drawn after it.
        #expect(window.performKeyEquivalent(with: try commandKey("a", code: kVK_ANSI_A, in: window)))
        NSPasteboard.general.clearContents()
        #expect(window.performKeyEquivalent(with: try commandKey("c", code: kVK_ANSI_C, in: window)))
        #expect(NSPasteboard.general.string(forType: .string) == "echo t")
    }

    @Test("Right-arrow at the end takes the suggestion: the value is the whole entry, and nothing runs")
    internal func suggestionTaken() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.history.record("touch took-it")
        fixture.panel.show()
        try type("touch t", in: fixture)
        #expect(fixture.window.shownSuggestion == "ook-it")
        try tap(.right, in: fixture)
        #expect(fixture.look() == Look.clean.with(input: "touch took-it"))
        #expect(try cursorAtEnd(fixture))
        #expect(fixture.panel.suggestion == nil)
        #expect(fixture.window.shownSuggestion == nil)
        try tap(.right, in: fixture)
        #expect(fixture.window.input.stringValue == "touch took-it")
        #expect(!fixture.panel.isBusy)
        #expect(try await children().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.home + "/took-it"))
    }

    @Test("Return with a suggestion showing runs the typed text only")
    internal func suggestionNotRun() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.history.record("echo two")
        fixture.panel.show()
        try type("echo t", in: fixture)
        #expect(fixture.window.shownSuggestion == "wo")
        try tap(.enter, in: fixture)
        try await fixture.until { !fixture.panel.isBusy }
        #expect(fixture.panel.state == .done(.status(0), retry: nil))
        #expect(fixture.window.transcript.string == "t\n")
        #expect(fixture.history.entries == ["echo t", "echo two"])
    }

    @Test("No suggestion after a macro's load, a list choice or a clear, nor while the list is open")
    internal func noSuggestionAfterLoad() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        // "echo t" is a load's text; "echo two" starts with it and is longer.
        fixture.history.record("echo two")
        fixture.history.record("echo t")
        fixture.settings.macros = ["echo t"]
        let window = fixture.window
        fixture.panel.show()
        press(try commandDigit(1, in: window), in: window)
        #expect(window.input.stringValue == "echo t")
        #expect(fixture.panel.suggestion == nil && window.shownSuggestion == nil)

        try tap(.escape, in: fixture)
        try tap(.down, in: fixture)
        #expect(window.recall.rows.first == "echo t")
        try tap(.enter, in: fixture)
        #expect(window.input.stringValue == "echo t")
        #expect(fixture.panel.suggestion == nil && window.shownSuggestion == nil)

        try tap(.escape, in: fixture)
        try type("echo t", in: fixture)
        #expect(window.shownSuggestion == "wo")
        try tap(.escape, in: fixture)
        #expect(fixture.look() == .clean)
        #expect(fixture.panel.suggestion == nil && window.shownSuggestion == nil)

        try type("echo t", in: fixture)
        try tap(.down, in: fixture)
        #expect(window.recall.isOpen)
        #expect(fixture.panel.suggestion == nil && window.shownSuggestion == nil)
        try type("w", in: fixture)
        #expect(window.recall.rows == ["echo two"])
        #expect(fixture.panel.suggestion == nil && window.shownSuggestion == nil)
    }

    @Test("No suggestion with the cursor moved left; Right-arrow then moves the cursor and takes nothing")
    internal func noSuggestionAfterLeft() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        fixture.history.record("echo two")
        fixture.panel.show()
        try type("echo t", in: fixture)
        #expect(fixture.window.shownSuggestion == "wo")
        try tap(.left, in: fixture)
        #expect(fixture.panel.suggestion == nil && fixture.window.shownSuggestion == nil)
        try tap(.right, in: fixture)
        #expect(try cursorAtEnd(fixture))
        #expect(fixture.window.input.stringValue == "echo t")
        #expect(fixture.panel.suggestion == nil && fixture.window.shownSuggestion == nil)
    }
}

// The four modifier keys decide the editing equivalents, as they decide the macros and Command-Q (ho-05.2
// Decision 10).
extension PanelTests {
    @Test("Caps Lock on: Command-A, C, X and V each act in the input; Command-C with it empty copies the transcript")
    internal func editingWithCapsLock() async throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let saved = savePasteboard()
        defer { restorePasteboard(saved) }
        let window = fixture.window
        let pasteboard = NSPasteboard.general
        fixture.panel.show()
        fixture.panel.submit("echo shown")
        #expect(try await fixture.done() == .done(.status(0), retry: nil))

        pasteboard.clearContents()
        #expect(window.performKeyEquivalent(with: try commandKey("c", code: kVK_ANSI_C, capsLock: true, in: window)))
        #expect(pasteboard.string(forType: .string) == "shown\n")

        window.input.stringValue = "typed text"
        let editor = try fieldEditor(fixture)
        editor.setSelectedRange(NSRange(location: 3, length: 0))
        #expect(window.performKeyEquivalent(with: try commandKey("a", code: kVK_ANSI_A, capsLock: true, in: window)))
        #expect(editor.selectedRange() == NSRange(location: 0, length: 10))
        pasteboard.clearContents()
        #expect(window.performKeyEquivalent(with: try commandKey("c", code: kVK_ANSI_C, capsLock: true, in: window)))
        #expect(pasteboard.string(forType: .string) == "typed text")
        #expect(window.performKeyEquivalent(with: try commandKey("x", code: kVK_ANSI_X, capsLock: true, in: window)))
        #expect(window.input.stringValue.isEmpty)
        #expect(pasteboard.string(forType: .string) == "typed text")
        #expect(window.performKeyEquivalent(with: try commandKey("v", code: kVK_ANSI_V, capsLock: true, in: window)))
        #expect(window.input.stringValue == "typed text")
        #expect(fixture.panel.state == .done(.status(0), retry: nil))
    }
}
