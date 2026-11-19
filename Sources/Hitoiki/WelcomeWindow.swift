import AppKit
import Carbon.HIToolbox

/// The welcome window: what the first launch shows, so a first-time user can tell the app started.
///
/// The app has no Dock icon, and a menu bar icon alone does not say how to open the panel. The application
/// makes the window at that launch only, and never again.
///
/// Built as About is: 360 points wide, the Theme's colours, a transparent title bar, movable by its background
/// and centred. Its face is AppKit's own labels and buttons, so a test reads each line and sends each button's
/// action as a click does.
///
/// Open Hitoiki closes it and shows the panel. Change the Shortcut, there only when the launch could not
/// register the shortcut, closes it and opens settings. Escape and the close button close it and show nothing.
@MainActor
internal final class WelcomeWindow: NSWindow {
    /// The width every line wraps within: the window's 360 points less 28 on each side, as About's text.
    private static let textWidth: CGFloat = 304

    /// Closes the window and shows the panel; the default button unless Change the Shortcut is there.
    internal let openButton = NSButton()
    /// Closes the window and opens settings; there, and the default button, only when the launch could not
    /// register the shortcut.
    internal let changeButton: NSButton?

    private let open: @MainActor () -> Void
    private let changeShortcut: @MainActor () -> Void

    /// The window for the launch's shortcut.
    ///
    /// - Parameters:
    ///   - shortcut: The combination the launch registered, or tried to.
    ///   - registered: Whether the launch registered it.
    ///   - menuBarShown: Whether the menu bar setting is on.
    ///   - open: What Open Hitoiki does after the window closes: shows the panel.
    ///   - changeShortcut: What Change the Shortcut does after the window closes: opens settings.
    internal init(
        shortcut: Shortcut.Combination,
        registered: Bool,
        menuBarShown: Bool,
        open: @escaping @MainActor () -> Void,
        changeShortcut: @escaping @MainActor () -> Void
    ) {
        self.open = open
        self.changeShortcut = changeShortcut
        changeButton = registered ? nil : NSButton()
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true)
        title = "Welcome to Hitoiki"
        isReleasedWhenClosed = false
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        backgroundColor = Theme.Token.ground.nsColor
        openButton.title = "Open Hitoiki"
        openButton.action = #selector(openPressed)
        changeButton?.title = "Change the Shortcut"
        changeButton?.action = #selector(changePressed)
        for button in buttons {
            button.bezelStyle = .push
            button.target = self
        }
        // Return presses the default button: Change the Shortcut when it is there, else Open Hitoiki.
        (changeButton ?? openButton).keyEquivalent = "\r"
        let content = face(
            shortcutLines: Self.shortcutLines(shortcut, registered: registered), menuBarShown: menuBarShown)
        contentView = content
        setContentSize(content.fittingSize)
        center()
    }

    /// Open Hitoiki, then Change the Shortcut when it is there: the default button on the right, as macOS
    /// places it.
    private var buttons: [NSButton] {
        [openButton] + (changeButton.map { [$0] } ?? [])
    }

    /// Escape closes the window, whatever has the keyboard, as the close button does.
    override internal func sendEvent(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard event.type == .keyDown, Int(event.keyCode) == kVK_Escape, modifiers.isEmpty else {
            return super.sendEvent(event)
        }
        performClose(nil)
    }

    /// The lines about the shortcut.
    ///
    /// Registered, the line naming it, and under it, while it is the default, the default spelled out; not
    /// registered, the line saying it couldn't be set up.
    private static func shortcutLines(_ shortcut: Shortcut.Combination, registered: Bool) -> [NSTextField] {
        let symbols = Shortcut.displayName(shortcut)
        guard registered else {
            return [
                label([
                    (symbols, Theme.Token.accent),
                    (" couldn't be set up. Another app or macOS may already be using it.", Theme.Token.ink),
                ])
            ]
        }
        let named = label([
            ("Press ", Theme.Token.ink), (symbols, Theme.Token.accent), (" to open it from any app.", Theme.Token.ink),
        ])
        guard shortcut == Settings.defaultShortcut else { return [named] }
        return [named, label([("(Control-Command-Space)", Theme.Token.inkFaint)], size: 12)]
    }

    @objc
    private func openPressed() {
        close()
        open()
    }

    @objc
    private func changePressed() {
        close()
        changeShortcut()
    }

    /// The face, top to bottom: the icon, the name line, the shortcut's lines, the menu bar line, the
    /// settings line, and the buttons.
    private func face(shortcutLines: [NSTextField], menuBarShown: Bool) -> NSView {
        let icon = NSImageView(image: NSApplication.shared.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 92),
            icon.heightAnchor.constraint(equalToConstant: 92),
        ])
        // The About window's name style.
        let name = Self.label([("Hitoiki is running", Theme.Token.ink)], size: 18, weight: .semibold)
        let menuBar = Self.label([
            (
                menuBarShown
                    ? "Hitoiki has no Dock icon. Its icon is in the menu bar, and you can turn that off in Settings."
                    : "Hitoiki has no Dock icon. You can show its icon in the menu bar from Settings.",
                Theme.Token.ink
            )
        ])
        let settingsLine = Self.label([("In the panel, ⌘, (Command-comma) opens Settings.", Theme.Token.ink)])
        let buttonRow = NSStackView(views: buttons)
        buttonRow.spacing = 12

        let stack = NSStackView(views: [icon, name] + shortcutLines + [menuBar, settingsLine, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 22, right: 28)
        stack.setCustomSpacing(14, after: icon)
        stack.setCustomSpacing(18, after: name)
        for line in shortcutLines.dropLast() {
            stack.setCustomSpacing(4, after: line)
        }
        if let last = shortcutLines.last { stack.setCustomSpacing(14, after: last) }
        stack.setCustomSpacing(10, after: menuBar)
        stack.setCustomSpacing(20, after: settingsLine)

        let root = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            stack.widthAnchor.constraint(equalToConstant: 360),
        ])
        return root
    }

    /// A centred line wrapping within the text width, each run in its own colour token.
    private static func label(
        _ runs: [(text: String, colour: Palette)], size: CGFloat = 13, weight: NSFont.Weight = .regular
    ) -> NSTextField {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let text = NSMutableAttributedString()
        for run in runs {
            text.append(
                NSAttributedString(
                    string: run.text,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: size, weight: weight),
                        .foregroundColor: run.colour.nsColor,
                        .paragraphStyle: paragraph,
                    ]))
        }
        let field = NSTextField(wrappingLabelWithString: "")
        field.alignment = .center
        field.isSelectable = false
        field.attributedStringValue = text
        field.preferredMaxLayoutWidth = textWidth
        return field
    }
}
