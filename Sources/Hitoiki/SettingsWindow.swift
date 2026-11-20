import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The settings window: one titled AppKit window hosting the SwiftUI form, above a footer that stays in view
/// while the form scrolls.
///
/// Made once for the app's life; its close button and Escape hide it, and the next Settings… brings back
/// the same window where it was. Command-Q quits from it as from the panel, Command-1 to Command-9 put
/// the keyboard in that macro's box, and the standard edit keys reach the box that has the keyboard. Return
/// in a box, or a click on the window's background, takes the keyboard out of it.
@MainActor
internal final class SettingsWindow: NSWindow {
    /// Where Command-Q sends the terminate selector: the application.
    ///
    /// The application's delegate kills a running command before the app ends. A test stands a recorder in
    /// its place, so the selector is witnessed unsent.
    internal var application: NSResponder = NSApplication.shared
    /// About Hitoiki, Help and Check for Updates, pinned under the form.
    internal let footer: SettingsFooter
    /// The panel this window was opened from, shown again as it was when the window closes; nil when it was
    /// opened from the menu bar item (ho-06.1 Decision 21).
    internal weak var origin: Panel?

    private let updateCheck: UpdateCheck

    /// The standard edit keys with Command alone: an accessory app has no Edit menu to route them
    /// (ho-06.3 Decision 9).
    ///
    /// AppKit declares no Swift method for `undo:`, so it is named by its string: the window answers it, and
    /// redo:, for the Edit menu's Undo and Redo, with its own undo manager, which the field editor's typing
    /// registers with.
    private static let editKeys: [String: Selector] = [
        "x": #selector(NSText.cut(_:)), "c": #selector(NSText.copy(_:)),
        "v": #selector(NSText.paste(_:)), "a": #selector(NSText.selectAll(_:)),
        "z": undo,
    ]
    /// Command-Z: Undo.
    private static let undo = Selector(("undo:"))
    /// Shift-Command-Z: Redo, named by its string as `undo:` is.
    private static let redo = Selector(("redo:"))

    /// The window over `content`, its footer showing `updateCheck` and sending About Hitoiki to `about`.
    internal init(content: SettingsView, updateCheck: UpdateCheck, about: @escaping @MainActor () -> Void) {
        self.updateCheck = updateCheck
        footer = SettingsFooter(about: about) { Task { await updateCheck.manual() } }
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 680),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true)
        title = "Hitoiki Settings"
        isReleasedWhenClosed = false
        let host = NSHostingView(rootView: content)
        // The window keeps its size; the form scrolls inside it, and the footer is outside the scrolling area.
        host.sizingOptions = []
        let root = NSView()
        for view in [host, footer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            ])
        }
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: root.topAnchor),
            host.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        contentView = root
        center()
        let footer = footer
        updateCheck.observe { footer.show($0) }
    }

    /// The manual check's answer goes as the window closes, by its close button, Escape or anything else, and
    /// the panel it was opened from comes back as the hotkey shows it.
    override internal func close() {
        super.close()
        updateCheck.dismissAnswer()
        let panel = origin
        origin = nil
        panel?.show()
    }

    /// Command-Q quits and Command-1 to Command-9 go to their macro's box, whatever in the window has the
    /// keyboard; Command-comma does nothing here; Command-X, C, V, A and Z and Shift-Command-Z go to the text
    /// box that has the keyboard, as the Edit menu would send them.
    ///
    /// An accessory app has no menu to route them. The four modifier keys alone decide each, as on the panel,
    /// so Caps Lock does not stop them. Taken before the views, the shortcut recorder included: a global
    /// Command-N would take the panel's own macro keys, so the recorder has no use for one (ho-05.2 Decisions
    /// 11, 14 and 15). The edit keys are taken only while a text box has the keyboard, so the recorder still
    /// records them.
    override internal func performKeyEquivalent(with event: NSEvent) -> Bool {
        let held = event.modifierFlags.intersection([.control, .option, .shift, .command])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if let text = firstResponder as? NSTextView, let action = Self.editAction(key, held) {
            let before = text.string
            guard text.tryToPerform(action, with: nil) else { return super.performKeyEquivalent(with: event) }
            // Undo and Redo change the text without the form hearing of it, so the store kept the text from
            // before; the box is told, as typing tells it, and the store follows.
            if action == Self.undo || action == Self.redo, text.string != before { text.didChangeText() }
            return true
        }
        guard held == .command else { return super.performKeyEquivalent(with: event) }
        if key == "q" {
            _ = application.tryToPerform(#selector(NSApplication.terminate(_:)), with: self)
            return true
        }
        // Command-comma opens settings from the panel; settings are already here, and it goes nowhere else.
        if key == "," { return true }
        guard let slot = Int(key), (1...Settings.macroSlots).contains(slot) else {
            return super.performKeyEquivalent(with: event)
        }
        focusMacro(slot)
        return true
    }

    /// Escape hides the window as the close button does, whatever has the keyboard, but for the two that own
    /// Escape: the shortcut recorder while it records, where Escape cancels the recording, and a text input
    /// method composing, where it cancels the composition (ho-05.1 Decision 13).
    ///
    /// Return or keypad Enter in a text box, and a click on the window's background, end the box's editing:
    /// the keyboard leaves the box, and its value, stored at every change, stays (ho-06.3 Decision 9).
    ///
    /// Taken here, before the first responder: a macro's box would otherwise keep Escape for completion and
    /// Return for itself, and the window would never see either. A click goes on as before; its place is read
    /// first.
    override internal func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            let background = onBackground(event)
            super.sendEvent(event)
            if background, textHasKeyboard { makeFirstResponder(nil) }
            return
        }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let composing = (firstResponder as? NSTextView)?.hasMarkedText() == true
        guard event.type == .keyDown, modifiers.isEmpty, !composing else { return super.sendEvent(event) }
        let code = Int(event.keyCode)
        if code == kVK_Escape, (firstResponder as? RecorderView)?.isRecording != true {
            performClose(nil)
        } else if code == kVK_Return || code == kVK_ANSI_KeypadEnter, textHasKeyboard {
            // The window itself takes the keyboard: the box's editing ends.
            makeFirstResponder(nil)
        } else {
            super.sendEvent(event)
        }
    }

    /// The action of an edit key: Command with X, C, V, A or Z, or Shift-Command-Z; nil for any other key.
    private static func editAction(_ key: String, _ held: NSEvent.ModifierFlags) -> Selector? {
        if held == [.command, .shift] { return key == "z" ? redo : nil }
        return held == .command ? editKeys[key] : nil
    }

    /// True while a text box has the keyboard: its field editor is the first responder.
    private var textHasKeyboard: Bool { (firstResponder as? NSTextView)?.isFieldEditor == true }

    /// True when `event` lands on the window's background: inside the content, and on no control, text, or
    /// the shortcut recorder, nor inside one.
    private func onBackground(_ event: NSEvent) -> Bool {
        guard let content = contentView, let frame = content.superview,
            var view = content.hitTest(frame.convert(event.locationInWindow, from: nil))
        else { return false }
        while view !== content {
            if view is NSControl || view is NSText || view is RecorderView { return false }
            guard let parent = view.superview else { return false }
            view = parent
        }
        return true
    }

    /// Puts the keyboard in the box of the macro numbered `slot`, the cursor at the end of its text.
    ///
    /// The box is scrolled into view, nothing is selected, and nothing else changes. The macros'
    /// nine boxes are the form's only text inputs, in slot order from the top.
    private func focusMacro(_ slot: Int) {
        let boxes = Self.descendants(of: contentView)
            .compactMap { $0 as? NSTextField }
            .filter(\.isEditable)
            .sorted { $0.convert($0.bounds, to: nil).minY > $1.convert($1.bounds, to: nil).minY }
        guard boxes.count == Settings.macroSlots else { return }
        let box = boxes[slot - 1]
        box.scrollToVisible(box.bounds)
        guard makeFirstResponder(box), let editor = box.currentEditor() else { return }
        // Taking the keyboard selects the box's whole text; the cursor goes to its end instead.
        editor.selectedRange = NSRange(location: (editor.string as NSString).length, length: 0)
    }

    private static func descendants(of view: NSView?) -> [NSView] {
        guard let view else { return [] }
        return view.subviews + view.subviews.flatMap { descendants(of: $0) }
    }
}

/// The settings footer: About Hitoiki, Help and Check for Updates, one centred row with ordinary padding; the
/// manual check's answer is in the form, under the update switch.
@MainActor
internal final class SettingsFooter: NSView {
    /// Internal, with the check button, so a test sends each one's action as a click does.
    internal let aboutButton = NSButton()
    /// Opens the site's documentation in the default browser, as the menu's Hitoiki Help does.
    internal let helpButton = NSButton()
    /// Runs a manual check; reads "Checking…" while one is in flight.
    internal let checkButton = NSButton()

    private let about: @MainActor () -> Void
    private let check: @MainActor () -> Void

    internal init(about: @escaping @MainActor () -> Void, check: @escaping @MainActor () -> Void) {
        self.about = about
        self.check = check
        super.init(frame: .zero)
        aboutButton.title = "About Hitoiki"
        helpButton.title = "Help"
        checkButton.title = "Check for Updates"
        for (button, action) in [
            (aboutButton, #selector(aboutPressed)), (helpButton, #selector(helpPressed)),
            (checkButton, #selector(checkPressed)),
        ] {
            button.bezelStyle = .push
            button.target = self
            button.action = action
        }
        lay()
    }

    @available(*, unavailable)
    internal required init?(coder: NSCoder) {
        nil
    }

    /// The check button's title, from `updateCheck` as it stands.
    internal func show(_ updateCheck: UpdateCheck) {
        checkButton.title = updateCheck.checking ? "Checking…" : "Check for Updates"
    }

    @objc
    private func aboutPressed() {
        about()
    }

    @objc
    private func helpPressed() {
        NSWorkspace.shared.open(UpdateCheck.docs)
    }

    @objc
    private func checkPressed() {
        check()
    }

    private func lay() {
        let rule = NSBox()
        rule.boxType = .separator
        let buttons = NSStackView(views: [aboutButton, helpButton, checkButton])
        buttons.spacing = 12
        buttons.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        for view in [rule, buttons] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            rule.leadingAnchor.constraint(equalTo: leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor),
            rule.topAnchor.constraint(equalTo: topAnchor),
            buttons.topAnchor.constraint(equalTo: rule.bottomAnchor),
            buttons.bottomAnchor.constraint(equalTo: bottomAnchor),
            buttons.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }
}
