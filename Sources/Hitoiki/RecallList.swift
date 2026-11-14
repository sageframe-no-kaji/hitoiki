import AppKit

/// The recall list: past commands under the input, newest first, ten rows in view.
///
/// A borderless child window of the panel with the panel's card look, the cards' width, its top just under
/// the bar card; it lies over whatever is below, and the panel does not move. It never takes the keyboard:
/// the input keeps it the whole time, so typing goes on into the input and the click-out rule never fires
/// from a click on a row. Panel decides what it shows and when; the list draws the rows, marks the selected
/// one, and hands a clicked row back to Panel.
@MainActor
internal final class RecallList: NSPanel {
    /// Rows in view; the rest by scrolling.
    internal static let visibleRows = 10
    /// One row: a line of the transcript's font and a little air.
    internal static let rowHeight = (TranscriptView.lineHeight + 6).rounded(.up)
    /// Between the bar card and the list: the panel's space between its two cards.
    private static let gap: CGFloat = 8
    /// Inside the card, above the first row and below the last.
    private static let margin: CGFloat = 4
    /// Where a row's text starts and ends: the bar's inset and the input's own padding, so a row reads under
    /// the input's text.
    private static let indent: CGFloat = 14

    /// The controller a clicked row goes to.
    internal weak var panel: Panel?
    /// Kept as shown, so a choice loads the row on screen, not a fresh read of a file that may have changed
    /// since.
    internal private(set) var rows: [String] = []
    /// The selected row: the top whenever the rows change.
    internal private(set) var selected = 0
    /// The one faint row shown when there are no rows.
    internal private(set) var placeholder = ""

    private let card = PanelWindow.cardBox()
    private let scroll = NSScrollView()
    private let canvas = Rows()

    /// The list, laid out and off screen.
    internal init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        canvas.list = self
        scroll.documentView = canvas
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let root = NSView()
        root.addSubview(card)
        root.addSubview(scroll)
        contentView = root
    }

    // The input keeps the keyboard while the list is open.
    override internal var canBecomeKey: Bool { false }

    override internal var canBecomeMain: Bool { false }

    /// True from Panel's opening of the list until its closing.
    internal var isOpen: Bool { parent != nil }

    /// Shows `rows`, or `placeholder` alone when there are none, the top row selected, under `anchor`.
    ///
    /// The list hangs from the bottom of `anchor`, the bar card, at the cards' width, and becomes a child of
    /// its window, so it moves with the panel. Showing it again while it is open places it again.
    internal func show(_ rows: [String], placeholder: String, under anchor: NSView) {
        self.rows = rows
        self.placeholder = placeholder
        selected = 0
        guard let owner = anchor.window else { return }
        let bar = owner.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let lines = CGFloat(max(rows.count, 1))
        let height = min(lines, CGFloat(Self.visibleRows)) * Self.rowHeight + 2 * Self.margin
        let place = NSRect(x: bar.minX, y: bar.minY - Self.gap - height, width: bar.width, height: height)
        setFrame(place, display: false)
        let bounds = contentView?.bounds ?? .zero
        card.frame = bounds
        scroll.frame = bounds.insetBy(dx: 0, dy: Self.margin)
        canvas.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: lines * Self.rowHeight)
        canvas.needsDisplay = true
        if parent == nil { owner.addChildWindow(self, ordered: .above) }
        orderFront(nil)
        canvas.scrollToVisible(area(ofRow: 0))
    }

    /// Moves the selection to `row`, kept within the rows, and scrolls it into view.
    internal func select(_ row: Int) {
        selected = min(max(row, 0), max(rows.count - 1, 0))
        canvas.needsDisplay = true
        canvas.scrollToVisible(area(ofRow: selected))
    }

    /// Takes the list off the panel and off screen.
    internal func withdraw() {
        guard isOpen || isVisible else { return }
        parent?.removeChildWindow(self)
        orderOut(nil)
    }

    /// The middle of `row` in this window's coordinates: where a click on the row lands.
    internal func location(ofRow row: Int) -> NSPoint {
        let rect = area(ofRow: row)
        return canvas.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
    }

    private func area(ofRow row: Int) -> NSRect {
        NSRect(x: 0, y: CGFloat(row) * Self.rowHeight, width: canvas.bounds.width, height: Self.rowHeight)
    }

    /// A click on a row chooses it; a click on the placeholder or below the rows does nothing.
    private func clicked(at point: NSPoint) {
        let row = Int((point.y / Self.rowHeight).rounded(.down))
        guard rows.indices.contains(row) else { return }
        panel?.choose(row: row)
    }

    /// The rows in `dirty`: each command on one line, a long one cut with "…" at its end, the selected row on
    /// a ground of the accent colour and in it; or the placeholder alone, faint.
    private func drawRows(in dirty: NSRect) {
        guard !rows.isEmpty else { return drawText(placeholder, in: area(ofRow: 0), color: Theme.Token.inkFaint) }
        let first = max(Int((dirty.minY / Self.rowHeight).rounded(.down)), 0)
        let last = min(Int((dirty.maxY / Self.rowHeight).rounded(.up)), rows.count)
        guard first < last else { return }
        for row in first..<last {
            let rect = area(ofRow: row)
            guard row == selected else {
                drawText(rows[row], in: rect, color: Theme.Token.ink)
                continue
            }
            Theme.Token.accent.nsColor.withAlphaComponent(0.15).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 6, dy: 1), xRadius: 5, yRadius: 5).fill()
            drawText(rows[row], in: rect, color: Theme.Token.accent)
        }
    }

    private func drawText(_ text: String, in rect: NSRect, color: Palette) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let line = NSRect(
            x: rect.minX + Self.indent,
            y: rect.midY - TranscriptView.lineHeight / 2,
            width: max(rect.width - 2 * Self.indent, 0),
            height: TranscriptView.lineHeight)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: TranscriptView.font, .foregroundColor: color.nsColor, .paragraphStyle: style,
        ]
        let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        (text as NSString).draw(with: line, options: options, attributes: attributes)
    }

    /// The rows' canvas, flipped so row zero is at the top: it draws through the list and hands it a click.
    private final class Rows: NSView {
        weak var list: RecallList?

        override var isFlipped: Bool { true }

        // The list never becomes key, so its first click must act rather than only make it key.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            list?.clicked(at: convert(event.locationInWindow, from: nil))
        }

        override func draw(_ dirtyRect: NSRect) {
            list?.drawRows(in: dirtyRect)
        }
    }
}
