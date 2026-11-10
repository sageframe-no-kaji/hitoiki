import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers

/// The settings page, one form: the eight settings, then the nine macros.
///
/// The shortcut, where commands start, the terminal, the appearance, the three switches and Refresh
/// Environment. Bound to the store: every change is written as it is made, and there is no Apply.
internal struct SettingsView: View {
    @Bindable internal var settings: Settings
    /// The recorder's candidate, through `Hotkey.record`: nil once it is the hotkey, or the refusal.
    internal let record: @MainActor (UInt32?, UInt32) -> String?
    /// Refresh Environment.
    internal let refresh: @MainActor () -> Void
    /// The line under the recorder when nothing is refused: what is registered, or why nothing is.
    internal let hotkeyLine: @MainActor () -> String

    @State private var refusal: String?

    internal init(
        settings: Settings,
        record: @escaping @MainActor (UInt32?, UInt32) -> String?,
        refresh: @escaping @MainActor () -> Void,
        hotkeyLine: @escaping @MainActor () -> String
    ) {
        self.settings = settings
        self.record = record
        self.refresh = refresh
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
                Picker("Open in Terminal uses", selection: terminalChoice) {
                    ForEach(terminalChoices, id: \.self) { identifier in
                        Text(Terminals.name(of: identifier)).tag(TerminalChoice.app(identifier))
                    }
                    Divider()
                    Text("Other…").tag(TerminalChoice.other)
                }
                Picker("Appearance", selection: $settings.appearance) {
                    Text("System").tag(Appearance.system)
                    Text("Light").tag(Appearance.light)
                    Text("Dark").tag(Appearance.dark)
                }
                .pickerStyle(.segmented)
            }
            Section {
                Toggle("Keep a history of commands", isOn: $settings.historyEnabled)
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
                LabeledContent("Login environment") {
                    Button("Refresh Environment") { refresh() }
                }
            }
            Section("Macros") {
                ForEach(0..<Settings.macroSlots, id: \.self) { slot in
                    HStack {
                        Text("⌘\(slot + 1)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        TextField("Name", text: macro(slot, \.name))
                            .frame(width: 120)
                        TextField("Command", text: macro(slot, \.command))
                            .font(.system(.body, design: .monospaced))
                    }
                    .labelsHidden()
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Home, the fixed folder, or the folder chooser.
    private enum DirectoryChoice: Hashable {
        case home
        case fixed
        case other
    }

    /// A terminal by bundle identifier, or the application chooser.
    private enum TerminalChoice: Hashable {
        case app(String)
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

    /// Terminal.app, the other known terminals installed, and the stored one when it is neither.
    private var terminalChoices: [String] {
        let installed = Terminals.installed()
        return installed.contains(settings.terminal) ? installed : installed + [settings.terminal]
    }

    private var terminalChoice: Binding<TerminalChoice> {
        let settings = settings
        return Binding {
            .app(settings.terminal)
        } set: { choice in
            switch choice {
            case .app(let identifier):
                settings.terminal = identifier
            case .other:
                Task { @MainActor in Self.chooseTerminal(into: settings) }
            }
        }
    }

    private func macro(_ slot: Int, _ field: WritableKeyPath<Macro, String> & Sendable) -> Binding<String> {
        let settings = settings
        return Binding {
            settings.macros[slot][keyPath: field]
        } set: { text in
            settings.macros[slot][keyPath: field] = text
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
/// It reads raw key codes and modifier flags, not characters. Escape cancels.
private final class RecorderView: NSView {
    var shortcut: Shortcut.Combination {
        didSet { needsDisplay = true }
    }
    var begin: @MainActor () -> Void
    var record: @MainActor (UInt32?, UInt32) -> Void

    private var recording = false {
        didSet { needsDisplay = true }
    }
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
