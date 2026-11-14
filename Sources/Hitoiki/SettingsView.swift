import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The settings page: one form of the settings, Clear History…, then the nine macros.
///
/// Bound to the store: every change is written as it is made, and there is no Apply. There is no Quit button:
/// Command-Q quits from this window as from the panel. The form scrolls; About Hitoiki and Check for Updates
/// are in the window's footer, outside it. Open at Login is kept by macOS, not the store.
internal struct SettingsView: View {
    @Bindable internal var settings: Settings
    /// What Clear History… clears: the file and the session's commands.
    internal let history: History
    /// The recorder's candidate, through `Hotkey.record`: nil once it is the hotkey, or the refusal.
    internal let record: @MainActor (UInt32?, UInt32) -> String?
    /// The line under the recorder when nothing is refused: what is registered, or why nothing is.
    internal let hotkeyLine: @MainActor () -> String
    /// The update check, whose manual answer shows under the update switch.
    internal let updateCheck: UpdateCheck
    /// Open at Login, through the system's login-item service.
    internal let loginItem: LoginItem

    @State private var refusal: String?
    @State private var confirmingClear = false
    /// Why the last Clear left the file: shown under Clear History… until a Clear succeeds or the window
    /// closes (ho-05.2.1).
    @State private var clearFailure: String?

    internal init(
        settings: Settings,
        history: History,
        record: @escaping @MainActor (UInt32?, UInt32) -> String?,
        hotkeyLine: @escaping @MainActor () -> String,
        updateCheck: UpdateCheck,
        loginItem: LoginItem
    ) {
        self.settings = settings
        self.history = history
        self.record = record
        self.hotkeyLine = hotkeyLine
        self.updateCheck = updateCheck
        self.loginItem = loginItem
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
            Section { switches }
            // One command box a row, bordered and with its placeholder, so an empty row shows where to type.
            Section("Macros") {
                // The nine lines are one form row, stacked with a 5-point gap between the boxes, so they stand
                // 32 points apart with no dividers between them: the grouped form held its own rows at least 37
                // points apart and drew dividers it would not hide. Every other section keeps its rows and
                // dividers (ho-05.2 Decision 16).
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
        // The window is made once and hidden on close, so the form's state outlives a close; the failed
        // Clear's line does not.
        .background(
            WindowCloseWatch {
                clearFailure = nil
                loginItem.dismiss()
            }
        )
        .alert("Delete your command history?", isPresented: $confirmingClear) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { clearFailure = history.clear() }
        } message: {
            Text("This can't be undone.")
        }
    }

    /// History, the menu bar item, Open at Login and the update check, each with what it says under it.
    @ViewBuilder private var switches: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Clear works with history off, so a file left from before can go.
            HStack {
                Text("Keep a history of commands")
                Spacer()
                Button("Clear History…") { confirmingClear = true }
                Toggle("Keep a history of commands", isOn: $settings.historyEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            // How a command with a secret in it runs unkept.
            Text("Commands that start with a space are not kept.")
                .font(.caption)
                .foregroundStyle(.secondary)
            // A Clear that could not delete the file says so: its commands are still recalled.
            if let clearFailure {
                Text(clearFailure)
                    .font(.caption)
                    .foregroundStyle(Theme.Token.alarm.color)
            }
        }
        Toggle("Show in the menu bar", isOn: $settings.menuBarEnabled)
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Open at Login", isOn: openAtLogin)
                .disabled(!loginItem.available)
            if let line = loginItem.line {
                Text(line)
                    .font(.caption)
                    .foregroundStyle(Theme.Token.alarm.color)
            }
        }
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Check for updates automatically", isOn: $settings.updateCheckEnabled)
            Text(
                "When Hitoiki opens and once a day, it asks GitHub for the latest version. Only the app's "
                    + "name and version are sent."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            // Only after a manual check, until the window closes.
            if let answer = updateCheck.answer {
                AnswerLine(answer: answer)
            }
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

    // The system's state, not the store's: a change goes to the service and the switch shows what it then
    // reports.
    private var openAtLogin: Binding<Bool> {
        let item = loginItem
        return Binding {
            item.isOn
        } set: { on in
            item.set(on)
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

/// The manual check's answer: the failure in the alarm colour with a link to the site, a newer release in the
/// accent colour and wholly a link, up to date in the secondary grey.
private struct AnswerLine: View {
    let answer: UpdateCheck.Answer

    var body: some View {
        Group {
            switch answer {
            case .failed:
                HStack(spacing: 6) {
                    Text(answer.text)
                        .foregroundStyle(Theme.Token.alarm.color)
                    Link("Visit \(UpdateCheck.siteName)", destination: UpdateCheck.site)
                }
            case .available:
                Link(answer.text, destination: UpdateCheck.site)
                    .foregroundStyle(Theme.Token.accent.color)
            case .upToDate:
                Text(answer.text)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .tint(Theme.Token.accent.color)
    }
}
