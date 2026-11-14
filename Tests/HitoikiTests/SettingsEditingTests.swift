import AppKit
import Carbon.HIToolbox
import Foundation
import Testing

@testable import Hitoiki

/// The settings window, shown, over a throwaway store holding `macros` and a history in a folder the test
/// owns and removes.
@MainActor
private struct ShownSettings {
    let suite: ThrowawaySuite
    let settings: Settings
    let root: URL
    let app: HitoikiApp
    let window: SettingsWindow

    init(macros: [String]) throws {
        let suite = try ThrowawaySuite()
        let settings = Settings(defaults: suite.defaults)
        settings.macros = macros
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "hitoiki-editing-" + UUID().uuidString)
        let history = History(folder: root.appending(path: "Hitoiki")) { settings.historyEnabled }
        let app = HitoikiApp(settings: settings, history: history)
        app.showSettings(nil)
        self.suite = suite
        self.settings = settings
        self.root = root
        self.app = app
        window = try #require(app.settingsWindow)
    }

    func remove() {
        window.orderOut(nil)
        suite.remove()
        try? FileManager.default.removeItem(at: root)
    }

    /// Puts the keyboard in a macro's box, the cursor where asked, and returns the box and its editor.
    func edit(slot: Int, cursor: Int) async throws -> (box: NSTextField, editor: NSTextView) {
        let boxes = try await shownBoxes(in: window)
        let box = boxes[slot - 1]
        #expect(window.makeFirstResponder(box))
        let editor = try #require(window.firstResponder as? NSTextView)
        #expect(editor.delegate === box)
        editor.setSelectedRange(NSRange(location: cursor, length: 0))
        return (box, editor)
    }
}

/// The macros' nine boxes in the shown settings window, from the top, once the form has laid them out.
@MainActor
private func shownBoxes(in window: NSWindow) async throws -> [NSTextField] {
    func boxes() -> [NSTextField] {
        views(under: window.contentView).compactMap { $0 as? NSTextField }.filter(\.isEditable)
    }
    try await until { boxes().count == Settings.macroSlots }
    // Window coordinates rise upward: the first row is the highest.
    return boxes().sorted { $0.convert($0.bounds, to: nil).minY > $1.convert($1.bounds, to: nil).minY }
}

/// Every view under `view`, depth first.
@MainActor
private func views(under view: NSView?) -> [NSView] {
    guard let view else { return [] }
    return view.subviews + view.subviews.flatMap { views(under: $0) }
}

/// A left click at `point`, in window coordinates, as the window receives it: the button down, then up.
@MainActor
private func click(at point: NSPoint, in window: NSWindow) throws {
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
        let event = try #require(
            NSEvent.mouseEvent(
                with: type,
                location: point,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: type == .leftMouseDown ? 1 : 0))
        window.sendEvent(event)
    }
}

/// Waits up to two seconds for `condition` and goes on either way: the expectation after it says what was seen.
@MainActor
private func settle(_ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + .seconds(2)
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(5))
    }
}

/// True when no text box in `window` has the keyboard.
@MainActor
private func noBoxEditing(in window: NSWindow) -> Bool {
    (window.firstResponder as? NSTextView)?.isFieldEditor != true
}

// The standard edit keys, Return, and a click on the background in the settings window (ho-06.3 Decision 9).
// In the settings-window suite, which runs inside the Panel suite, one test at a time.
extension PanelTests.SettingsWindowTests {
    @Test("Command-A, C, X and V reach the macro box with the keyboard; the store follows; Caps Lock changes nothing")
    internal func editKeysInAMacroBox() async throws {
        let shown = try ShownSettings(macros: ["echo one"])
        defer { shown.remove() }
        let saved = savePasteboard()
        defer { restorePasteboard(saved) }
        let window = shown.window
        let pasteboard = NSPasteboard.general
        let (_, editor) = try await shown.edit(slot: 1, cursor: 0)

        let commandA = try key("a", code: UInt16(kVK_ANSI_A), modifiers: .command, in: window)
        #expect(window.performKeyEquivalent(with: commandA))
        #expect(editor.selectedRange() == NSRange(location: 0, length: 8))

        pasteboard.clearContents()
        let commandC = try key("c", code: UInt16(kVK_ANSI_C), modifiers: .command, in: window)
        #expect(window.performKeyEquivalent(with: commandC))
        #expect(pasteboard.string(forType: .string) == "echo one")
        #expect(editor.string == "echo one")

        pasteboard.clearContents()
        let commandX = try key("x", code: UInt16(kVK_ANSI_X), modifiers: .command, in: window)
        #expect(window.performKeyEquivalent(with: commandX))
        #expect(pasteboard.string(forType: .string) == "echo one")
        #expect(editor.string.isEmpty)
        try await until { shown.settings.macros[0].isEmpty }

        pasteboard.clearContents()
        pasteboard.setString("uptime", forType: .string)
        let commandV = try key("v", code: UInt16(kVK_ANSI_V), modifiers: .command, in: window)
        #expect(window.performKeyEquivalent(with: commandV))
        #expect(editor.string == "uptime")
        try await until { shown.settings.macros[0] == "uptime" }

        let capsLockV = try key("V", code: UInt16(kVK_ANSI_V), modifiers: [.command, .capsLock], in: window)
        #expect(window.performKeyEquivalent(with: capsLockV))
        #expect(editor.string == "uptimeuptime")
        try await until { shown.settings.macros[0] == "uptimeuptime" }

        // The keyboard stayed in the box, and the window stayed.
        #expect(window.firstResponder === editor)
        #expect(window.isVisible)
    }

    @Test("Command-Z undoes the last change in the macro box with the keyboard; Shift-Command-Z redoes it")
    internal func undoAndRedoInAMacroBox() async throws {
        let shown = try ShownSettings(macros: ["", "echo two"])
        defer { shown.remove() }
        let saved = savePasteboard()
        defer { restorePasteboard(saved) }
        let window = shown.window
        let (_, editor) = try await shown.edit(slot: 2, cursor: 8)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(" more", forType: .string)
        let commandV = try key("v", code: UInt16(kVK_ANSI_V), modifiers: .command, in: window)
        #expect(window.performKeyEquivalent(with: commandV))
        #expect(editor.string == "echo two more")
        await settle { shown.settings.macros[1] == "echo two more" }
        #expect(shown.settings.macros[1] == "echo two more")

        let commandZ = try key("z", code: UInt16(kVK_ANSI_Z), modifiers: .command, in: window)
        #expect(window.performKeyEquivalent(with: commandZ))
        #expect(editor.string == "echo two")
        await settle { shown.settings.macros[1] == "echo two" }
        #expect(shown.settings.macros[1] == "echo two")

        let shiftCommandZ = try key("Z", code: UInt16(kVK_ANSI_Z), modifiers: [.command, .shift], in: window)
        #expect(window.performKeyEquivalent(with: shiftCommandZ))
        #expect(editor.string == "echo two more")
        await settle { shown.settings.macros[1] == "echo two more" }
        #expect(shown.settings.macros[1] == "echo two more")
        #expect(window.firstResponder === editor)
    }

    @Test("Return, or keypad Enter, in a macro box takes the keyboard out of it; the box and the store keep the text")
    internal func returnEndsEditing() async throws {
        let shown = try ShownSettings(macros: [])
        defer { shown.remove() }
        let window = shown.window
        let (box, editor) = try await shown.edit(slot: 1, cursor: 0)
        editor.insertText("echo kept", replacementRange: editor.selectedRange())
        try await until { shown.settings.macros[0] == "echo kept" }

        window.sendEvent(try key("\r", code: UInt16(kVK_Return), in: window))
        #expect(noBoxEditing(in: window))
        #expect(box.currentEditor() == nil)
        #expect(box.stringValue == "echo kept")
        #expect(shown.settings.macros[0] == "echo kept")
        #expect(window.isVisible)

        let (second, enterEditor) = try await shown.edit(slot: 2, cursor: 0)
        enterEditor.insertText("uptime", replacementRange: enterEditor.selectedRange())
        try await until { shown.settings.macros[1] == "uptime" }
        let enter = try key("\u{03}", code: UInt16(kVK_ANSI_KeypadEnter), modifiers: .numericPad, in: window)
        window.sendEvent(enter)
        #expect(noBoxEditing(in: window))
        #expect(second.currentEditor() == nil)
        #expect(shown.settings.macros == ["echo kept", "uptime", "", "", "", "", "", "", ""])
        #expect(window.isVisible)
    }

    @Test("A click on the window's background, in the form or the footer, takes the keyboard out of a macro box")
    internal func backgroundClickEndsEditing() async throws {
        let shown = try ShownSettings(macros: ["echo one"])
        defer { shown.remove() }
        let window = shown.window
        let footer = window.footer

        // The footer's leading margin, beside its buttons.
        let (box, _) = try await shown.edit(slot: 1, cursor: 8)
        try click(at: footer.convert(NSPoint(x: 4, y: footer.bounds.midY), to: nil), in: window)
        #expect(noBoxEditing(in: window))
        #expect(box.currentEditor() == nil)
        #expect(box.stringValue == "echo one")

        // The form's leading margin, level with the box.
        _ = try await shown.edit(slot: 1, cursor: 8)
        let row = box.convert(box.bounds, to: nil)
        try click(at: NSPoint(x: 4, y: row.midY), in: window)
        #expect(noBoxEditing(in: window))
        #expect(box.currentEditor() == nil)
        #expect(shown.settings.macros[0] == "echo one")
        #expect(window.isVisible)
    }
}
