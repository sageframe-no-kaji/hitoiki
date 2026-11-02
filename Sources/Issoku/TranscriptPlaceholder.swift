import AppKit

/// The plain stand-in for ho-04's Transcript.
///
/// Every chunk as UTF-8 text, monospace, no colour, no carriage-return handling, no ceiling. While a
/// command runs it holds the keyboard and hands each key to Panel, so nothing typed is drawn here.
@MainActor
internal final class TranscriptPlaceholder: NSTextView {
    internal weak var panel: Panel?

    /// A block after the last byte while a command runs.
    ///
    /// Drawn, never stored: `string` holds only what the command sent.
    internal var showsCursor = false {
        didSet { needsDisplay = true }
    }

    /// The monospace font, with its line height; the panel's input, terminal size and height cap read both.
    internal static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    internal static let lineHeight = NSLayoutManager().defaultLineHeight(for: font)
    private static let block = NSSize(
        width: ("M" as NSString).size(withAttributes: [.font: font]).width, height: lineHeight)

    private let attributes: [NSAttributedString.Key: Any] = [
        .font: TranscriptPlaceholder.font,
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

    override internal func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard showsCursor, let layout = layoutManager, let container = textContainer else { return }
        layout.ensureLayout(for: container)
        // The extra line fragment exists when the text is empty or ends a line; otherwise the block
        // follows the last glyph on its line.
        var corner = layout.extraLineFragmentRect.origin
        corner.x += container.lineFragmentPadding
        if layout.extraLineFragmentRect.height == 0, layout.numberOfGlyphs > 0 {
            let last = layout.numberOfGlyphs - 1
            corner.x = layout.boundingRect(forGlyphRange: NSRange(location: last, length: 1), in: container).maxX
            corner.y = layout.lineFragmentRect(forGlyphAt: last, effectiveRange: nil).minY
        }
        corner.x += textContainerOrigin.x
        corner.y += textContainerOrigin.y
        Theme.Token.ink.nsColor.setFill()
        NSRect(origin: corner, size: Self.block).fill()
    }

    override internal func paste(_ sender: Any?) {
        panel?.keystroke(.paste)
    }

    internal func append(_ text: String) {
        textStorage?.append(NSAttributedString(string: text, attributes: attributes))
        // The block moves with the end of the text, outside the range the text system redraws.
        if showsCursor { needsDisplay = true }
        scrollToEndOfDocument(nil)
    }
}
