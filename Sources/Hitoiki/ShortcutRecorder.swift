import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The shortcut row: the form's wrapper for the recorder's capturing view.
internal struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: Shortcut.Combination
    let begin: @MainActor () -> Void
    let record: @MainActor (UInt32?, UInt32) -> Void

    func makeNSView(context: Context) -> RecorderView {
        RecorderView(shortcut: shortcut, begin: begin, record: record)
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.shortcut = shortcut
        view.begin = begin
        view.record = record
    }
}

/// The recorder: the current combination until clicked, then "Type a shortcut" and the keyboard.
///
/// It reads raw key codes and modifier flags, not characters. Escape cancels; the settings window asks
/// `isRecording` so its own Escape leaves a recording to the recorder (ho-05.1 Decision 13).
internal final class RecorderView: NSView {
    var shortcut: Shortcut.Combination {
        didSet { needsDisplay = true }
    }
    var begin: @MainActor () -> Void
    var record: @MainActor (UInt32?, UInt32) -> Void

    private var recording = false {
        didSet { needsDisplay = true }
    }

    /// True from the click that starts a recording until a key, a release, Escape or losing the keyboard ends it.
    var isRecording: Bool { recording }
    /// The modifiers held since the recording began, for a release with no key.
    private var held: UInt32 = 0

    init(
        shortcut: Shortcut.Combination,
        begin: @escaping @MainActor () -> Void,
        record: @escaping @MainActor (UInt32?, UInt32) -> Void
    ) {
        self.shortcut = shortcut
        self.begin = begin
        self.record = record
        super.init(frame: NSRect(x: 0, y: 0, width: 180, height: 24))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard window?.makeFirstResponder(self) == true else { return }
        held = 0
        recording = true
        begin()
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { return super.keyDown(with: event) }
        take(event)
    }

    // A key with Command reaches the window's key equivalents before `keyDown`.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording, window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        take(event)
        return true
    }

    override func flagsChanged(with event: NSEvent) {
        guard recording else { return super.flagsChanged(with: event) }
        let now = Shortcut.carbonModifiers(event.modifierFlags)
        if now != 0 {
            held |= now
            needsDisplay = true
        } else if held != 0 {
            finish(keyCode: nil, modifiers: held)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let frame = bounds.insetBy(dx: 0.5, dy: 0.5)
        let shape = NSBezierPath(roundedRect: frame, xRadius: 5, yRadius: 5)
        NSColor.controlBackgroundColor.setFill()
        shape.fill()
        (recording ? NSColor.keyboardFocusIndicatorColor : NSColor.separatorColor).setStroke()
        shape.lineWidth = recording ? 2 : 1
        shape.stroke()
        let text: String
        if recording {
            text = held == 0 ? "Type a shortcut" : Shortcut.symbols(held)
        } else {
            text = Shortcut.displayName(shortcut)
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: recording && held == 0 ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(
            at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
    }

    private func take(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        let modifiers = Shortcut.carbonModifiers(event.modifierFlags)
        if Int(event.keyCode) == kVK_Escape, modifiers == 0 {
            recording = false
            window?.makeFirstResponder(nil)
            return
        }
        finish(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }

    private func finish(keyCode: UInt32?, modifiers: UInt32) {
        recording = false
        window?.makeFirstResponder(nil)
        record(keyCode, modifiers)
    }
}
