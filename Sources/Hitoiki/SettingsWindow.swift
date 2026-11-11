import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The settings window: one titled AppKit window hosting the SwiftUI form, the one place System Design §5
/// lets SwiftUI in.
///
/// Made once for the app's life; its close button and Escape hide it, and the next Settings… brings back
/// the same window where it was. Command-Q quits from it as from the panel (ho-05.2 Decision 11), and
/// Command-1 to Command-9 put the keyboard in that macro's box (Decision 14).
@MainActor
internal final class SettingsWindow: NSWindow {
    /// Where Command-Q sends the terminate selector: the application.
    ///
    /// The application's delegate kills a running command before the app ends. A test stands a recorder in
    /// its place, so the selector is witnessed unsent.
    internal var application: NSResponder = NSApplication.shared

    internal init(content: SettingsView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 680),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true)
        title = "Hitoiki Settings"
        isReleasedWhenClosed = false
        let host = NSHostingView(rootView: content)
        // The window keeps its size; the form scrolls inside it.
        host.sizingOptions = []
        contentView = host
        center()
    }

    /// Command-Q quits and Command-1 to Command-9 go to their macro's box, whatever in the window has the
    /// keyboard; Command-comma does nothing here (ho-05.2 Decisions 11, 14 and 15).
    ///
    /// An accessory app has no menu to route them. The four modifier keys alone decide each, as on the panel,
    /// so Caps Lock does not stop them. Taken before the views, the shortcut recorder included: a global
    /// Command-N would take the panel's own macro keys, so the recorder has no use for one.
    override internal func performKeyEquivalent(with event: NSEvent) -> Bool {
        let held = event.modifierFlags.intersection([.control, .option, .shift, .command])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        guard held == .command else { return super.performKeyEquivalent(with: event) }
        if key == "q" {
            _ = application.tryToPerform(#selector(NSApplication.terminate(_:)), with: self)
            return true
        }
        // Command-comma opens settings from the panel; settings are already here, and it goes nowhere else.
        if key == "," { return true }
        guard let slot = Int(key), (1...Settings.macroSlots).contains(slot) else {
            return super.performKeyEquivalent(with: event)
        }
        focusMacro(slot)
        return true
    }

    /// Escape hides the window as the close button does (ho-05.1 Decision 13), whatever has the keyboard,
    /// but for the two that own Escape: the shortcut recorder while it records, where Escape cancels the
    /// recording, and a text input method composing, where it cancels the composition.
    ///
    /// Taken here, before the first responder: a macro's box would otherwise keep Escape for completion and
    /// the window would never see it.
    override internal func sendEvent(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard event.type == .keyDown, Int(event.keyCode) == kVK_Escape, modifiers.isEmpty,
            (firstResponder as? RecorderView)?.isRecording != true,
            (firstResponder as? NSTextView)?.hasMarkedText() != true
        else { return super.sendEvent(event) }
        performClose(nil)
    }

    /// Puts the keyboard in the box of the macro numbered `slot`, the cursor at the end of its text.
    ///
    /// The box is scrolled into view, nothing is selected, and nothing else changes (Decision 14). The macros'
    /// nine boxes are the form's only text inputs, in slot order from the top.
    private func focusMacro(_ slot: Int) {
        let boxes = Self.descendants(of: contentView)
            .compactMap { $0 as? NSTextField }
            .filter(\.isEditable)
            .sorted { $0.convert($0.bounds, to: nil).minY > $1.convert($1.bounds, to: nil).minY }
        guard boxes.count == Settings.macroSlots else { return }
        let box = boxes[slot - 1]
        box.scrollToVisible(box.bounds)
        guard makeFirstResponder(box), let editor = box.currentEditor() else { return }
        // Taking the keyboard selects the box's whole text; the cursor goes to its end instead.
        editor.selectedRange = NSRange(location: (editor.string as NSString).length, length: 0)
    }

    private static func descendants(of view: NSView?) -> [NSView] {
        guard let view else { return [] }
        return view.subviews + view.subviews.flatMap { descendants(of: $0) }
    }
}
