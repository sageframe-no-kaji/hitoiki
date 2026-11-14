import AppKit
import HitoikiCore

/// The application: no Dock icon, and a menu bar item only when the setting is on; one store, one history,
/// one update check, one Run, one Panel, one hotkey, one settings window and one About window for its life.
///
/// It owns the three live effects: the shortcut, through `Hotkey.record`; the menu bar item and the
/// appearance, each following its setting.
@main
@MainActor
internal final class HitoikiApp: NSObject, NSApplicationDelegate {
    /// The settings window, made at the first Settings… and the same window every time after.
    internal private(set) var settingsWindow: SettingsWindow?
    /// The About window, made at the first About Hitoiki and the same window every time after.
    internal private(set) var aboutWindow: AboutWindow?

    private let settings: Settings
    /// Made at launch over the app's folder in Application Support, and shared by the panel, which writes
    /// and recalls, and settings, whose Clear History… clears it.
    private let history: History
    /// The update check: at launch and daily from `applicationDidFinishLaunching`, and from Check for Updates.
    private let updateCheck: UpdateCheck
    /// Open at Login, read again each time settings is shown.
    private let loginItem: LoginItem
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
        updateCheck = UpdateCheck(
            version: UpdateCheck.runningVersion(), enabled: { settings.updateCheckEnabled }, fetch: UpdateCheck.send)
        loginItem = LoginItem(bundleIdentifier: Bundle.main.bundleIdentifier, service: LoginItem.system)
        super.init()
    }

    /// The app over `settings`, `history`, `updateCheck` and `loginItem`, for a test.
    ///
    /// Without a check given, the app's check has no version, so it can never send a request; without a login
    /// item given, the app's has no bundle identifier, so it never calls the login-item service.
    internal init(
        settings: Settings, history: History, updateCheck: UpdateCheck? = nil, loginItem: LoginItem? = nil
    ) {
        self.settings = settings
        self.history = history
        self.updateCheck = updateCheck ?? UpdateCheck(version: nil, enabled: { false }, fetch: UpdateCheck.send)
        self.loginItem = loginItem ?? LoginItem(bundleIdentifier: nil, service: LoginItem.system)
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
        updateCheck.observe { panel.announce($0.available) }
        updateCheck.begin()
    }

    // The recovery path when the hotkey never fires: relaunching the app brings the panel up. macOS sends
    // reopen only to a bundled app.
    internal func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel?.show()
        return false
    }

    /// Quit waits for a command still running, a start in flight, or a kill a clear sent and has not seen end.
    internal func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let panel, panel.isBusy || panel.awaitsClearedDone else { return .terminateNow }
        Task {
            await panel.killForQuit()
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// The gear's click and the menu bar item's Settings…, reached through the responder chain.
    ///
    /// Opened from the panel, by the gear or Command-comma, whose sender is the gear in the panel's window,
    /// settings hides the panel as a click-out does, and closing settings shows it again.
    /// Opened from the menu, it returns to nothing, unless it was already open from the panel.
    @objc
    internal func showSettings(_ sender: Any?) {
        let window = settingsWindow ?? makeSettingsWindow()
        settingsWindow = window
        if let panel = ((sender as? NSView)?.window as? PanelWindow)?.panel {
            window.origin = panel
            panel.hide()
        } else if !window.isVisible {
            window.origin = nil
        }
        // A change made in System Settings › General › Login Items shows here.
        loginItem.read()
        // An accessory app takes no typing until it is active. The deprecated forcing call, not activate():
        // macOS 14's cooperative activation refuses a request made from a key in a non-activating panel, so
        // Command-comma left settings behind the front app; Electron and OpenJDK use this call for the same
        // case. Marked to be deprecated in a future release; it builds without a warning (ho-05.2 Decision 17).
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// About Hitoiki, from the settings footer and the menu bar item: the one About window, in front.
    @objc
    internal func showAbout(_ sender: Any?) {
        let window = aboutWindow ?? AboutWindow(version: updateCheck.version)
        aboutWindow = window
        // The forcing call, as in showSettings and for the same reason.
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Check for Updates… in the menu bar item's menu: settings, with a manual check whose answer shows in the
    /// form under the update switch.
    @objc
    internal func checkForUpdates(_ sender: Any?) {
        showSettings(sender)
        Task { await updateCheck.manual() }
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
                hotkeyLine: { Hotkey.settingsLine(launch: status, attempted: attempted) },
                updateCheck: updateCheck,
                loginItem: loginItem),
            updateCheck: updateCheck
        ) { [weak self] in self?.showAbout(nil) }
    }
}
