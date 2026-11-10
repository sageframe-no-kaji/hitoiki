import AppKit
import SwiftUI

/// The settings window: one titled AppKit window hosting the SwiftUI form, the one place System Design §5
/// lets SwiftUI in.
///
/// Made once for the app's life; its close button hides it, and the next Settings… brings back the same
/// window where it was.
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
}
