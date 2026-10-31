import AppKit

/// The plain stand-in for ho-04's Transcript.
///
/// Every chunk as UTF-8 text, monospace, no colour, no carriage-return handling, no ceiling. While a
/// command runs it holds the keyboard and hands each key to Panel, so nothing typed is drawn here.
@MainActor
internal final class TranscriptPlaceholder: NSTextView {
    internal weak var panel: Panel?

    private let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
        .foregroundColor: Theme.Token.ink.nsColor,
    ]

    /// An empty, read-only view sized by its scroll view.
    internal init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 0))
        isEditable = false
        isSelectable = false
        drawsBackground = false
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = .width
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        textContainer?.widthTracksTextView = true
    }

    // NSTextView's `init(frame:)` builds its text system through this initializer.
    override private init(frame: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frame, textContainer: container)
    }

    @available(*, unavailable)
    internal required init?(coder: NSCoder) {
        nil
    }

    // Read-only and unselectable, the view would otherwise refuse the keyboard while a command runs.
    override internal var acceptsFirstResponder: Bool { true }

    override internal func keyDown(with event: NSEvent) {
        panel?.keystroke(
            Keystrokes.action(characters: event.characters, modifiers: event.modifierFlags, keyCode: event.keyCode))
    }

    override internal func paste(_ sender: Any?) {
        panel?.keystroke(.paste)
    }

    /// Appends `text` and scrolls to the end.
    internal func append(_ text: String) {
        textStorage?.append(NSAttributedString(string: text, attributes: attributes))
        scrollToEndOfDocument(nil)
    }
}
