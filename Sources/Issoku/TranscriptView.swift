import AppKit
import IssokuCore

/// The one monospace zone: what the command printed, drawn from the Transcript model.
///
/// The model is the source; the text storage is the rendered form of its lines and holds nothing
/// else. Each chunk edits the storage by the model's change. While a command runs the view holds
/// the keyboard and hands each key to Panel, so nothing typed is drawn here.
@MainActor
internal final class TranscriptView: NSTextView {
    internal weak var panel: Panel?

    /// A block after the last glyph of the line in progress while a command runs.
    ///
    /// Drawn, never stored: `string` holds only what the command sent.
    internal var showsCursor = false {
        didSet { needsDisplay = true }
    }

    /// True once the window has grown the transcript to its height cap; from then until `clear()`
    /// the height is fixed and the window does not measure the document.
    internal var atCap = false

    /// The transcript's font, with its line height; the terminal size and the height cap read both.
    internal static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    internal static let lineHeight = NSLayoutManager().defaultLineHeight(for: font)
    private static let boldFont = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .bold)
    private static let block = NSSize(
        width: ("M" as NSString).size(withAttributes: [.font: font]).width, height: lineHeight)
    private static let ink = Theme.Token.ink.nsColor
    private static let colors = Theme.transcriptColors.map(\.nsColor)
    private static let newline = NSAttributedString(string: "\n", attributes: [.font: font, .foregroundColor: ink])

    private var model = Transcript()
    /// The UTF-16 length of the line in progress, the last thing in the storage.
    private var inProgressLength = 0

    /// An empty, read-only, selectable view sized by its scroll view.
    internal init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 0))
        isEditable = false
        isSelectable = true
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

    // The keyboard comes here while a command runs, whatever the text system would answer.
    override internal var acceptsFirstResponder: Bool { true }

    override internal func keyDown(with event: NSEvent) {
        // No command runs: the key is the input's, so Escape still dismisses (System Design 2.1).
        guard showsCursor else {
            (window as? PanelWindow)?.typeInInput(event)
            return
        }
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
        Self.ink.setFill()
        NSRect(origin: corner, size: Self.block).fill()
    }

    override internal func paste(_ sender: Any?) {
        panel?.keystroke(.paste)
    }

    /// The selection as plain text, or the whole transcript when nothing is selected.
    override internal func copy(_ sender: Any?) {
        let text = string as NSString
        let selected = selectedRanges.map(\.rangeValue).filter { $0.length > 0 }.map(text.substring(with:))
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(selected.isEmpty ? string : selected.joined(separator: "\n"), forType: .string)
    }

    /// Feeds `chunk` to the model and edits the storage by the change; follows the end if it was in view.
    internal func append(_ chunk: [UInt8]) {
        let change = model.feed(chunk)
        guard let storage = textStorage else { return }
        let following = visibleRect.maxY >= bounds.maxY
        storage.beginEditing()
        if change.evicted > 0 {
            storage.deleteCharacters(in: NSRange(location: 0, length: Self.leadingLength(change.evicted, in: storage)))
        }
        let tail = NSMutableAttributedString()
        for line in change.committed {
            tail.append(Self.rendered(line))
            tail.append(Self.newline)
        }
        let inProgress = Self.rendered(change.inProgress)
        tail.append(inProgress)
        storage.replaceCharacters(
            in: NSRange(location: storage.length - inProgressLength, length: inProgressLength), with: tail)
        inProgressLength = inProgress.length
        storage.endEditing()
        // The block moves with the end of the text, outside the range the text system redraws.
        if showsCursor { needsDisplay = true }
        if following { scrollToEndOfDocument(nil) }
    }

    /// Forgets the model's lines and empties the storage.
    internal func clear() {
        model.clear()
        textStorage?.setAttributedString(NSAttributedString())
        inProgressLength = 0
        atCap = false
    }

    /// The UTF-16 length of the first `count` lines of `storage`, their LFs included.
    private static func leadingLength(_ count: Int, in storage: NSTextStorage) -> Int {
        let text = storage.mutableString
        var end = 0
        for _ in 0..<count {
            let rest = NSRange(location: end, length: text.length - end)
            let found = text.range(of: "\n", options: .literal, range: rest)
            guard found.location != NSNotFound else { break }
            end = NSMaxRange(found)
        }
        return end
    }

    /// One attributed range per span: the monospace font at its weight, the colour from Theme's table.
    private static func rendered(_ line: Transcript.Line) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for span in line.spans {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: span.style.bold ? boldFont : font,
                .foregroundColor: span.style.color.map { colors[Int($0)] } ?? ink,
            ]
            result.append(NSAttributedString(string: span.text, attributes: attributes))
        }
        return result
    }
}
