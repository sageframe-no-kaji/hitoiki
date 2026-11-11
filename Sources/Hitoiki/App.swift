import AppKit
import HitoikiCore

/// The application: no Dock icon, and a menu bar item only when the setting is on; one store, one history,
/// one Run, one Panel, one hotkey and one settings window for its life.
///
/// It owns the three live effects: the shortcut, through `Hotkey.record`; the menu bar item and the
/// appearance, each following its setting.
@main
@MainActor
internal final class HitoikiApp: NSObject, NSApplicationDelegate {
    /// The settings window, made at the first Settings… and the same window every time after.
    internal private(set) var settingsWindow: SettingsWindow?

    private let settings: Settings
    /// Made at launch over the app's folder in Application Support, and shared by the panel, which writes
    /// and recalls, and settings, whose Clear History… clears it.
    private let history: History
    private var panel: Panel?
    private var menuBar: MenuBarItem?
    /// The launch registration's status: settings names it while no combination is registered.
    private var launchStatus = noErr

    /// The app over the user's defaults and `~/Library/Application Support/Hitoiki/history.txt`.
    override internal init() {
        let settings = Settings(defaults: .standard)
        self.settings = settings
        let folder = URL.applicationSupportDirectory.appending(path: "Hitoiki", directoryHint: .isDirectory)
        history = History(folder: folder) { settings.historyEnabled }
        super.init()
    }

    /// The app over `settings` and `history`, for a test.
    internal init(settings: Settings, history: History) {
        self.settings = settings
        self.history = history
        super.init()
    }

    internal static func main() {
        let application = NSApplication.shared
        let delegate = HitoikiApp()
        application.delegate = delegate
        application.run()
        withExtendedLifetime(delegate) {}
    }

    internal func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        settings.follow({ $0.appearance }, apply: { NSApplication.shared.appearance = $0.nsAppearance })
        let run = Run(environment: ProcessInfo.processInfo.environment)
        let panel = Panel(
            run: run,
            launch: Task { try await run.refreshEnvironment() },
            window: PanelWindow(),
            settings: settings,
            history: history)
        let shortcut = settings.shortcut
        launchStatus = Hotkey.register(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) { panel.toggle() }
        if let notice = Hotkey.statusText(for: launchStatus, combination: shortcut) { panel.note(notice) }
        let menuBar = MenuBarItem { panel.show() }
        settings.follow({ $0.menuBarEnabled }, apply: { menuBar.isShown = $0 })
        self.panel = panel
        self.menuBar = menuBar
    }

    // The recovery path when the hotkey never fires. macOS sends reopen only to a bundled app; the
    // bundle is ho-06's, and so is the demonstration.
    internal func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel?.show()
        return false
    }

    internal func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let panel, panel.isBusy else { return .terminateNow }
        Task {
            await panel.killForQuit()
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// The gear's click and the menu bar item's Settings…, reached through the responder chain.
    @objc
    internal func showSettings(_ sender: Any?) {
        let window = settingsWindow ?? makeSettingsWindow()
        settingsWindow = window
        // An accessory app takes no typing until it is active. The deprecated forcing call, not activate():
        // macOS 14's cooperative activation refuses a request made from a key in a non-activating panel, so
        // Command-comma left settings behind the front app; Electron and OpenJDK use this call for the same
        // case (ho-05.2 Decision 17). Marked to be deprecated in a future release; it builds without a warning.
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeSettingsWindow() -> SettingsWindow {
        let settings = settings
        let attempted = settings.shortcut
        let status = launchStatus
        return SettingsWindow(
            content: SettingsView(
                settings: settings,
                history: history,
                record: { keyCode, modifiers in
                    Hotkey.record(
                        keyCode: keyCode, modifiers: modifiers, into: settings, system: Shortcut.systemShortcuts())
                },
                hotkeyLine: { Hotkey.settingsLine(launch: status, attempted: attempted) }))
    }
}
