import AppKit
import IssokuCore

/// The panel: one borderless, non-activating floating window, shown and hidden, never closed.
///
/// It takes the keyboard while the app underneath stays frontmost. Two cards: the bar, with the
/// input, the gear and the notice, always shown; and beneath it the output card, with the transcript
/// and the strip at its foot. Layout, placement, the strip and the gear menu live here; every event
/// goes to Panel.
@MainActor
internal final class PanelWindow: NSPanel, NSTextFieldDelegate {
    internal weak var panel: Panel?
    /// The command line: monospace, wrapping, up to five lines before it scrolls.
    internal let input = NSTextField()
    internal let status = NSTextField(labelWithString: "")
    internal let notice = NSTextField(wrappingLabelWithString: "")
    internal let retryButton = NSButton()
    internal let stopButton = NSButton()
    internal let openButton = NSButton()
    internal let copyButton = NSButton()
    internal let transcript = TranscriptView(width: width - 2 * inset)
    /// The input, the gear and the notice; in Composing, the whole panel.
    internal let bar = NSView()
    /// The transcript and the strip, beneath the bar; Panel shows it from Running until a dismissal.
    internal let outputCard = NSView()

    private static let width: CGFloat = 640
    private static let inset: CGFloat = 12
    /// The space between stacked rows, and between the two cards.
    private static let spacing: CGFloat = 8
    /// A card's margin above its first row and below its last.
    private static let margin: CGFloat = 10
    /// The input's own size, apart from the transcript's (ho-04 Decision 7).
    private static let inputSize: CGFloat = 18
    private static let inputFont = NSFont.monospacedSystemFont(ofSize: inputSize, weight: .regular)
    private static let inputLineHeight = NSLayoutManager().defaultLineHeight(for: inputFont)

    /// Command-key equivalents for the text in the panel; an accessory app has no menu to route them.
    private static let editing: [String: Selector] = [
        "x": #selector(NSText.cut(_:)), "c": #selector(NSText.copy(_:)),
        "v": #selector(NSText.paste(_:)), "a": #selector(NSText.selectAll(_:)),
    ]

    private let gear = NSButton()
    /// Built at the transcript's width: the transcript's width mask becomes a layout constraint against
    /// the clip view, and one made while the clip view had no width kept the transcript 616 points
    /// wider than the clip, so no line wrapped (ho-04 run sheet).
    private let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width - 2 * inset, height: 0))
    private let rule = PanelWindow.hairline()
    private let strip = NSStackView()
    private let gearMenu = NSMenu()
    private lazy var inputHeight = input.heightAnchor.constraint(equalToConstant: Self.inputLineHeight)
    private lazy var transcriptHeight = scroll.heightAnchor.constraint(equalToConstant: 0)
    /// The transcript's greatest height: half the screen's visible height, less the rest of the panel.
    private var cap: CGFloat = 0

    /// The panel, laid out and hidden.
    internal init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        level = .floating
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // The panel appears over the current app (System Design 2.1), even when that app is full screen.
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        input.isBordered = false
        input.drawsBackground = false
        input.focusRingType = .none
        input.font = Self.inputFont
        input.textColor = Theme.Token.ink.nsColor
        input.usesSingleLineMode = false
        input.cell?.wraps = true
        input.cell?.isScrollable = false
        input.lineBreakMode = .byCharWrapping
        input.delegate = self
        for label in [status, notice] {
            label.font = .systemFont(ofSize: 11)
            label.textColor = Theme.Token.inkFaint.nsColor
        }
        status.lineBreakMode = .byTruncatingTail
        status.setContentHuggingPriority(.defaultLow, for: .horizontal)
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        style(retryButton, "Retry", Theme.Token.accent, #selector(retryPressed))
        style(stopButton, "Stop", Theme.Token.alarm, #selector(stopPressed))
        style(openButton, "Open in Terminal", Theme.Token.accent, #selector(openPressed))
        style(copyButton, "Copy", Theme.Token.accent, #selector(NSText.copy(_:)))
        copyButton.target = transcript
        gear.isBordered = false
        gear.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        gear.contentTintColor = Theme.Token.inkFaint.nsColor
        gear.target = self
        gear.action = #selector(gearPressed)
        gearMenu.addItem(withTitle: "Settings…", action: #selector(IssokuApp.showSettings(_:)), keyEquivalent: "")
        gearMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")

        scroll.documentView = transcript
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        layOut()
    }

    override internal var canBecomeKey: Bool { true }

    override internal func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers ?? ""
        guard flags == .command, let action = Self.editing[key] else {
            return super.performKeyEquivalent(with: event)
        }
        // Command-C is the transcript's (System Design 2.3) unless text is selected in the input.
        let editor = input.currentEditor()
        if key == "c", firstResponder !== editor || editor?.selectedRange.length == 0 {
            transcript.copy(nil)
            return true
        }
        return firstResponder?.tryToPerform(action, with: nil) == true || super.performKeyEquivalent(with: event)
    }

    override internal func cancelOperation(_ sender: Any?) {
        panel?.dismissIfAllowed()
    }

    // The click-out: another window, in this app or another, took the keyboard.
    override internal func resignKey() {
        super.resignKey()
        panel?.dismissIfAllowed()
    }

    /// A key pressed in the transcript while no command runs: the input takes the keyboard and the key,
    /// as if it had been pressed there, so Escape dismisses, Return submits and characters type.
    internal func typeInInput(_ event: NSEvent) {
        makeFirstResponder(input)
        guard let editor = input.currentEditor() else { return }
        // Taking the keyboard selects the whole line; the key lands at its end instead.
        editor.selectedRange = NSRange(location: (editor.string as NSString).length, length: 0)
        editor.keyDown(with: event)
    }

    /// The terminal size for the next command: the transcript's width over the advance of `M`, and
    /// its greatest height over the line height.
    internal var terminalSize: WindowSize {
        let padding = 2 * (transcript.textContainer?.lineFragmentPadding ?? 0)
        let advance = ("M" as NSString).size(withAttributes: [.font: TranscriptView.font]).width
        let columns = ((Self.width - 2 * Self.inset - padding) / advance).rounded(.down)
        let rows = (cap / TranscriptView.lineHeight).rounded(.down)
        return WindowSize(columns: UInt16(max(columns, 1)), rows: UInt16(max(rows, 1)))
    }

    /// Puts the panel on the screen holding the mouse: centred, its top a quarter of the way down.
    internal func place() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        else { return }
        let visible = screen.visibleFrame
        setFrameTopLeftPoint(NSPoint(x: visible.midX - Self.width / 2, y: visible.maxY - visible.height / 4))
    }

    /// Sizes the input to its lines and the transcript to its text up to the cap, keeping the top edge.
    ///
    /// Once the transcript has reached the cap its height stays there until a clear, and the document
    /// is not measured again.
    internal func fit() {
        guard let content = contentView else { return }
        var lines: CGFloat = 1
        let editor = input.currentEditor() as? NSTextView
        if let layout = editor?.layoutManager, let container = editor?.textContainer {
            layout.ensureLayout(for: container)
            lines = (layout.usedRect(for: container).height / Self.inputLineHeight).rounded()
        }
        inputHeight.constant = min(max(lines, 1), 5) * Self.inputLineHeight

        // Shown while the cursor is on, so a command that has printed nothing yet still shows where keys go.
        let empty = transcript.string.isEmpty && !transcript.showsCursor
        scroll.isHidden = empty
        rule.isHidden = empty
        content.layoutSubtreeIfNeeded()
        // All but the transcript area, with a one-line input and the output card's chrome counted
        // whether or not the card is on screen: the rows a command is told are the rows it gets.
        let card = 2 * Self.margin + 2 * Self.spacing + rule.fittingSize.height + strip.fittingSize.height
        let rest = bar.frame.height - inputHeight.constant + Self.inputLineHeight + Self.spacing + card
        let visible = (screen ?? NSScreen.main)?.visibleFrame.height ?? 0
        cap = max(visible / 2 - rest, TranscriptView.lineHeight)
        if transcript.atCap {
            transcriptHeight.constant = cap
        } else if !empty, let layout = transcript.layoutManager, let container = transcript.textContainer {
            layout.ensureLayout(for: container)
            let text = layout.usedRect(for: container).height + 2 * transcript.textContainerInset.height
            transcript.atCap = text >= cap
            transcriptHeight.constant = min(text, cap)
        }
        content.layoutSubtreeIfNeeded()
        // Whole points: a fractional height set again on every chunk came back from the window server
        // alternately a point taller and shorter, and the panel jiggled (ho-04 run sheet, item 8).
        let height = content.fittingSize.height.rounded(.up)
        setFrame(NSRect(x: frame.minX, y: frame.maxY - height, width: Self.width, height: height), display: true)
        invalidateShadow()
    }

    internal func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            let flags = NSApplication.shared.currentEvent?.modifierFlags ?? []
            if flags.contains(.shift) || flags.contains(.option) {
                textView.insertNewlineIgnoringFieldEditor(nil)
            } else {
                panel?.submit(input.stringValue)
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            panel?.dismissIfAllowed()
            return true
        default:
            return false
        }
    }

    internal func controlTextDidChange(_ notification: Notification) {
        fit()
    }

    @objc
    private func retryPressed() {
        // The empty line takes the offer, through the same path as Return.
        panel?.submit("")
    }

    @objc
    private func stopPressed() {
        panel?.stop()
    }

    @objc
    private func openPressed() {
        panel?.openInTerminal()
    }

    @objc
    private func gearPressed() {
        gearMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: gear.bounds.height + 4), in: gear)
    }

    private func style(_ button: NSButton, _ title: String, _ color: Palette, _ action: Selector) {
        button.isBordered = false
        button.attributedTitle = NSAttributedString(
            string: title, attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: color.nsColor])
        button.target = self
        button.action = action
    }

    private func layOut() {
        // The input fills the row in every state and the gear sits at its trailing edge, centred top to
        // bottom; under the default gravity areas an input with nothing to edit took only its own width.
        let row = NSStackView(views: [input, gear])
        row.distribution = .fill
        row.alignment = .centerY
        row.spacing = Self.spacing
        gear.setContentHuggingPriority(.required, for: .horizontal)
        for control in [status, retryButton, stopButton, openButton, copyButton] {
            strip.addArrangedSubview(control)
        }
        strip.spacing = Self.spacing
        Self.card(bar, holding: [row, notice])
        Self.card(outputCard, holding: [scroll, rule, strip])
        let column = NSStackView(views: [bar, outputCard])
        column.orientation = .vertical
        column.spacing = Self.spacing
        let root = NSView()
        column.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            column.topAnchor.constraint(equalTo: root.topAnchor),
            column.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            bar.widthAnchor.constraint(equalTo: column.widthAnchor),
            outputCard.widthAnchor.constraint(equalTo: column.widthAnchor),
            root.widthAnchor.constraint(equalToConstant: Self.width), inputHeight, transcriptHeight,
        ])
        contentView = root
    }

    /// Makes `view` a card — ground, corner radius 10, a hairline border — with `views` stacked on it.
    private static func card(_ view: NSView, holding views: [NSView]) {
        let box = NSBox()
        box.boxType = .custom
        box.cornerRadius = 10
        box.borderWidth = 1
        box.fillColor = Theme.Token.ground.nsColor
        box.borderColor = Theme.Token.inkFaint.nsColor.withAlphaComponent(0.15)
        let column = NSStackView(views: views)
        column.orientation = .vertical
        column.spacing = spacing
        column.edgeInsets = NSEdgeInsets(top: margin, left: 0, bottom: margin, right: 0)
        for layer in [box, column] {
            layer.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(layer)
            NSLayoutConstraint.activate([
                layer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                layer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                layer.topAnchor.constraint(equalTo: view.topAnchor),
                layer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }
        for arranged in views {
            NSLayoutConstraint.activate([
                arranged.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: inset),
                arranged.trailingAnchor.constraint(equalTo: column.trailingAnchor, constant: -inset),
            ])
        }
    }

    private static func hairline() -> NSBox {
        let line = NSBox()
        line.boxType = .custom
        line.borderWidth = 0
        line.fillColor = Theme.Token.inkFaint.nsColor.withAlphaComponent(0.15)
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }
}
