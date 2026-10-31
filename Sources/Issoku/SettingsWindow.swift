import AppKit

/// The placeholder Settings window: one line about the hotkey, nothing else.
///
/// The real settings are ho-05's.
@MainActor
internal final class SettingsWindow: NSWindow {
    /// A titled window holding `text`.
    internal init(text: String) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 96),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true)
        title = "Issoku Settings"
        isReleasedWhenClosed = false
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(label)
        contentView = content
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        center()
    }
}
