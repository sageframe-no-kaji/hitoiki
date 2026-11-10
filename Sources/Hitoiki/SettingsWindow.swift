import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The settings window: one titled AppKit window hosting the SwiftUI form, the one place System Design §5
/// lets SwiftUI in.
///
/// Made once for the app's life; its close button and Escape hide it, and the next Settings… brings back
/// the same window where it was.
@MainActor
internal final class SettingsWindow: NSWindow {
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
}
