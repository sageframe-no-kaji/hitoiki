import AppKit
import IssokuCore

/// The panel: one borderless, non-activating floating window, shown and hidden, never closed.
///
/// It takes the keyboard while the app underneath stays frontmost. Layout, placement, the control
/// strip and the gear menu live here; every event goes to Panel.
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
    internal let transcript = TranscriptPlaceholder(width: width - 2 * inset)

    private static let width: CGFloat = 640
    private static let inset: CGFloat = 12
    private static let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private static let lineHeight = NSLayoutManager().defaultLineHeight(for: mono)

    /// Command-key equivalents for the text in the panel; an accessory app has no menu to route them.
    private static let editing: [String: Selector] = [
        "x": #selector(NSText.cut(_:)), "c": #selector(NSText.copy(_:)),
        "v": #selector(NSText.paste(_:)), "a": #selector(NSText.selectAll(_:)),
    ]

    private let gear = NSButton()
    private let scroll = NSScrollView()
    private let rule = PanelWindow.hairline()
    private let gearMenu = NSMenu()
    private lazy var inputHeight = input.heightAnchor.constraint(equalToConstant: Self.lineHeight)
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
        input.font = Self.mono
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
        guard flags == .command, let action = Self.editing[event.charactersIgnoringModifiers ?? ""] else {
            return super.performKeyEquivalent(with: event)
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

    /// The terminal size for the next command: the transcript's width over the advance of `M`, and
    /// its greatest height over the line height.
    internal var terminalSize: WindowSize {
        let padding = 2 * (transcript.textContainer?.lineFragmentPadding ?? 0)
        let advance = ("M" as NSString).size(withAttributes: [.font: Self.mono]).width
        let columns = ((Self.width - 2 * Self.inset - padding) / advance).rounded(.down)
        let rows = (cap / Self.lineHeight).rounded(.down)
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
    internal func fit() {
        guard let content = contentView else { return }
        var lines: CGFloat = 1
        let editor = input.currentEditor() as? NSTextView
        if let layout = editor?.layoutManager, let container = editor?.textContainer {
            layout.ensureLayout(for: container)
            lines = (layout.usedRect(for: container).height / Self.lineHeight).rounded()
        }
        inputHeight.constant = min(max(lines, 1), 5) * Self.lineHeight

        // Shown while the cursor is on, so a command that has printed nothing yet still shows where keys go.
        let empty = transcript.string.isEmpty && !transcript.showsCursor
        scroll.isHidden = empty
        rule.isHidden = empty
        transcriptHeight.constant = 0
        content.layoutSubtreeIfNeeded()
        let visible = (screen ?? NSScreen.main)?.visibleFrame.height ?? 0
        cap = max(visible / 2 - content.fittingSize.height, Self.lineHeight)
        if !empty, let layout = transcript.layoutManager, let container = transcript.textContainer {
            layout.ensureLayout(for: container)
            let text = layout.usedRect(for: container).height + 2 * transcript.textContainerInset.height
            transcriptHeight.constant = min(text, cap)
        }
        content.layoutSubtreeIfNeeded()
        let height = content.fittingSize.height
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

    /// Ground, a hairline edge and radius 10 behind a column: the input, a hairline, the control
    /// strip, the notice, a hairline, the transcript.
    private func layOut() {
        let card = NSBox()
        card.boxType = .custom
        card.cornerRadius = 10
        card.borderWidth = 1
        card.fillColor = Theme.Token.ground.nsColor
        card.borderColor = Theme.Token.inkFaint.nsColor.withAlphaComponent(0.15)
        let strip = NSStackView(views: [status, retryButton, stopButton, openButton, gear])
        strip.spacing = 8
        let column = NSStackView(views: [input, Self.hairline(), strip, notice, rule, scroll])
        column.orientation = .vertical
        column.spacing = 8
        column.edgeInsets = NSEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        let root = NSView()
        for view in [card, column] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                view.topAnchor.constraint(equalTo: root.topAnchor),
                view.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            ])
        }
        for view in column.arrangedSubviews {
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: column.leadingAnchor, constant: Self.inset),
                view.trailingAnchor.constraint(equalTo: column.trailingAnchor, constant: -Self.inset),
            ])
        }
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: Self.width), inputHeight, transcriptHeight,
        ])
        contentView = root
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
