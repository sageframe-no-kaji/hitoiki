import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers

/// The settings page: one form of the seven settings, Clear History…, then the nine macros.
///
/// The shortcut, where commands start, the terminal, the appearance and the three switches. Bound to the
/// store: every change is written as it is made, and there is no Apply. There is no Quit button: Command-Q
/// quits from this window as from the panel (ho-05.2 Decision 11).
internal struct SettingsView: View {
    @Bindable internal var settings: Settings
    /// What Clear History… clears: the file and the session's commands (ho-05.2 Decision 9).
    internal let history: History
    /// The recorder's candidate, through `Hotkey.record`: nil once it is the hotkey, or the refusal.
    internal let record: @MainActor (UInt32?, UInt32) -> String?
    /// The line under the recorder when nothing is refused: what is registered, or why nothing is.
    internal let hotkeyLine: @MainActor () -> String

    @State private var refusal: String?
    @State private var confirmingClear = false

    internal init(
        settings: Settings,
        history: History,
        record: @escaping @MainActor (UInt32?, UInt32) -> String?,
        hotkeyLine: @escaping @MainActor () -> String
    ) {
        self.settings = settings
        self.history = history
        self.record = record
        self.hotkeyLine = hotkeyLine
    }

    internal var body: some View {
        Form {
            Section {
                LabeledContent("Shortcut") {
                    ShortcutRecorder(shortcut: settings.shortcut) {
                        refusal = nil
                    } record: { keyCode, modifiers in
                        refusal = record(keyCode, modifiers)
                    }
                    .frame(width: 180, height: 24)
                }
                Text(refusal ?? hotkeyLine())
                    .font(.caption)
                    .foregroundStyle(refusal == nil ? Color.secondary : Theme.Token.alarm.color)
                Picker("Commands start in", selection: directoryChoice) {
                    Text("Home").tag(DirectoryChoice.home)
                    if let path = settings.directoryPath {
                        Text((path as NSString).abbreviatingWithTildeInPath).tag(DirectoryChoice.fixed)
                    }
                    Divider()
                    Text("Other…").tag(DirectoryChoice.other)
                }
                LabeledContent("Open in Terminal uses") {
                    // The closure captures the store alone, which is Sendable, and not the view.
                    let store = settings
                    TerminalPopUp(selected: store.terminal) { identifier in
                        guard let identifier else { return Self.chooseTerminal(into: store) }
                        store.terminal = identifier
                    }
                    .fixedSize()
                }
                Picker("Appearance", selection: $settings.appearance) {
                    Text("System").tag(Appearance.system)
                    Text("Light").tag(Appearance.light)
                    Text("Dark").tag(Appearance.dark)
                }
                .pickerStyle(.segmented)
            }
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Keep a history of commands", isOn: $settings.historyEnabled)
                    // The space rule (ho-05.2 Decision 12): how a command with a secret in it runs unkept.
                    Text("Commands that start with a space are not kept.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // It works with history off, so a file left from before can go.
                HStack {
                    Spacer()
                    Button("Clear History…") { confirmingClear = true }
                }
                Toggle("Show in the menu bar", isOn: $settings.menuBarEnabled)
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Check for updates automatically", isOn: $settings.updateCheckEnabled)
                    Text(
                        "Once a day, one request to GitHub for the latest release; nothing is sent but the app's "
                            + "name and version."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            // One command box a row, bordered and with its placeholder, so an empty row shows where to type
            // (ho-05.1 Decision 16).
            Section("Macros") {
                // The nine lines are one form row, stacked with a 5-point gap between the boxes, so they stand
                // 32 points apart with no dividers between them: the grouped form held its own rows at least 37
                // points apart and drew dividers it would not hide (ho-05.2 Decision 16). Every other section
                // keeps its rows and dividers.
                VStack(spacing: 5) {
                    ForEach(0..<Settings.macroSlots, id: \.self) { slot in
                        HStack {
                            Text("⌘\(slot + 1)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            TextField("⌘\(slot + 1)", text: macro(slot), prompt: Text("Command"))
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .alert("Delete your command history?", isPresented: $confirmingClear) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { history.clear() }
        } message: {
            Text("This can't be undone.")
        }
    }

    /// Home, the fixed folder, or the folder chooser.
    private enum DirectoryChoice: Hashable {
        case home
        case fixed
        case other
    }

    // The bindings capture the store alone, which is Sendable, and not the view.
    private var directoryChoice: Binding<DirectoryChoice> {
        let settings = settings
        return Binding {
            settings.directoryMode == .fixed && settings.directoryPath != nil ? .fixed : .home
        } set: { choice in
            switch choice {
            case .home:
                settings.directoryMode = .home
            case .fixed:
                settings.directoryMode = .fixed
            case .other:
                Task { @MainActor in Self.chooseFolder(into: settings) }
            }
        }
    }

    private func macro(_ slot: Int) -> Binding<String> {
        let settings = settings
        return Binding {
            settings.macros[slot]
        } set: { text in
            settings.macros[slot] = text
        }
    }

    private static func chooseFolder(into settings: Settings) {
        let chooser = NSOpenPanel()
        chooser.canChooseDirectories = true
        chooser.canChooseFiles = false
        chooser.allowsMultipleSelection = false
        chooser.prompt = "Choose"
        guard chooser.runModal() == .OK, let url = chooser.url else { return }
        settings.directoryPath = url.path
        settings.directoryMode = .fixed
    }

    private static func chooseTerminal(into settings: Settings) {
        let chooser = NSOpenPanel()
        chooser.allowedContentTypes = [.application]
        chooser.directoryURL = URL(fileURLWithPath: "/Applications")
        chooser.allowsMultipleSelection = false
        chooser.prompt = "Choose"
        guard chooser.runModal() == .OK, let url = chooser.url,
            let identifier = Terminals.identifier(ofApplicationAt: url)
        else { return }
        settings.terminal = identifier
    }
}

/// The terminal row's pop-up: Terminal.app, the other known terminals installed, the stored one when it is
/// neither, then Other….
///
/// An AppKit pop-up, where SwiftUI's picker builds its list once with the view: the list is read from
/// Launch Services each time the pop-up is about to open and each time the window becomes key, so a
/// terminal installed while the window stood open is offered (ho-05.1 Decision 15). Nothing is cached.
private struct TerminalPopUp: NSViewRepresentable {
    /// The stored bundle identifier, read in the form's body so a change redraws the row.
    let selected: String
    /// A terminal picked, by bundle identifier, or nil for Other….
    let choose: @MainActor (String?) -> Void

    func makeNSView(context: Context) -> TerminalPopUpButton {
        TerminalPopUpButton(selected: selected, choose: choose)
    }

    func updateNSView(_ view: TerminalPopUpButton, context: Context) {
        view.selected = selected
        view.choose = choose
        view.readList()
    }
}

private final class TerminalPopUpButton: NSPopUpButton, NSMenuDelegate {
    var selected: String
    var choose: @MainActor (String?) -> Void

    init(selected: String, choose: @escaping @MainActor (String?) -> Void) {
        self.selected = selected
        self.choose = choose
        super.init(frame: .zero, pullsDown: false)
        menu?.delegate = self
        target = self
        action = #selector(picked)
        readList()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        readList()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
        guard let window else { return }
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowBecameKey), name: NSWindow.didBecomeKeyNotification, object: window)
    }

    /// The list as Launch Services gives it now, with the stored terminal selected.
    func readList() {
        let installed = Terminals.installed()
        let identifiers = installed.contains(selected) ? installed : installed + [selected]
        removeAllItems()
        for identifier in identifiers {
            let item = NSMenuItem(title: Terminals.name(of: identifier), action: nil, keyEquivalent: "")
            item.representedObject = identifier
            menu?.addItem(item)
        }
        menu?.addItem(.separator())
        menu?.addItem(NSMenuItem(title: "Other…", action: nil, keyEquivalent: ""))
        selectItem(at: identifiers.firstIndex(of: selected) ?? 0)
    }

    @objc
    private func windowBecameKey() {
        readList()
    }

    @objc
    private func picked() {
        let identifier = selectedItem?.representedObject as? String
        choose(identifier)
        if let identifier { selected = identifier }
        // Other… cancelled leaves the stored terminal; the pop-up shows it again rather than "Other…".
        readList()
    }
}

/// The shortcut row: the form's wrapper for the recorder's capturing view.
private struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: Shortcut.Combination
    let begin: @MainActor () -> Void
    let record: @MainActor (UInt32?, UInt32) -> Void

    func makeNSView(context: Context) -> RecorderView {
        RecorderView(shortcut: shortcut, begin: begin, record: record)
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.shortcut = shortcut
        view.begin = begin
        view.record = record
    }
}

/// The recorder: the current combination until clicked, then "Type a shortcut" and the keyboard.
///
/// It reads raw key codes and modifier flags, not characters. Escape cancels; the settings window asks
/// `isRecording` so its own Escape (Decision 13) leaves a recording to the recorder.
internal final class RecorderView: NSView {
    var shortcut: Shortcut.Combination {
        didSet { needsDisplay = true }
    }
    var begin: @MainActor () -> Void
    var record: @MainActor (UInt32?, UInt32) -> Void

    private var recording = false {
        didSet { needsDisplay = true }
    }

    /// True from the click that starts a recording until a key, a release, Escape or losing the keyboard ends it.
    var isRecording: Bool { recording }
    /// The modifiers held since the recording began, for a release with no key.
    private var held: UInt32 = 0

    init(
        shortcut: Shortcut.Combination,
        begin: @escaping @MainActor () -> Void,
        record: @escaping @MainActor (UInt32?, UInt32) -> Void
    ) {
        self.shortcut = shortcut
        self.begin = begin
        self.record = record
        super.init(frame: NSRect(x: 0, y: 0, width: 180, height: 24))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard window?.makeFirstResponder(self) == true else { return }
        held = 0
        recording = true
        begin()
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { return super.keyDown(with: event) }
        take(event)
    }

    // A key with Command reaches the window's key equivalents before `keyDown`.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording, window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        take(event)
        return true
    }

    override func flagsChanged(with event: NSEvent) {
        guard recording else { return super.flagsChanged(with: event) }
        let now = Shortcut.carbonModifiers(event.modifierFlags)
        if now != 0 {
            held |= now
            needsDisplay = true
        } else if held != 0 {
            finish(keyCode: nil, modifiers: held)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let frame = bounds.insetBy(dx: 0.5, dy: 0.5)
        let shape = NSBezierPath(roundedRect: frame, xRadius: 5, yRadius: 5)
        NSColor.controlBackgroundColor.setFill()
        shape.fill()
        (recording ? NSColor.keyboardFocusIndicatorColor : NSColor.separatorColor).setStroke()
        shape.lineWidth = recording ? 2 : 1
        shape.stroke()
        let text: String
        if recording {
            text = held == 0 ? "Type a shortcut" : Shortcut.symbols(held)
        } else {
            text = Shortcut.displayName(shortcut)
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: recording && held == 0 ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(
            at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
    }

    private func take(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        let modifiers = Shortcut.carbonModifiers(event.modifierFlags)
        if Int(event.keyCode) == kVK_Escape, modifiers == 0 {
            recording = false
            window?.makeFirstResponder(nil)
            return
        }
        finish(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }

    private func finish(keyCode: UInt32?, modifiers: UInt32) {
        recording = false
        window?.makeFirstResponder(nil)
        record(keyCode, modifiers)
    }
}
