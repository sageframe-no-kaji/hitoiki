import AppKit
import HitoikiCore

/// The application: no Dock icon and no menu bar; one Run, one Panel and one hotkey for its life.
@main
@MainActor
internal final class HitoikiApp: NSObject, NSApplicationDelegate {
    private var panel: Panel?
    private var hotkey = noErr
    private var settings: SettingsWindow?

    internal static func main() {
        let application = NSApplication.shared
        let delegate = HitoikiApp()
        application.delegate = delegate
        application.run()
        withExtendedLifetime(delegate) {}
    }

    internal func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let run = Run(environment: ProcessInfo.processInfo.environment)
        let panel = Panel(run: run, launch: Task { try await run.refreshEnvironment() }, window: PanelWindow())
        let (keyCode, modifiers) = Hotkey.combination
        hotkey = Hotkey.register(keyCode: keyCode, modifiers: modifiers) { panel.toggle() }
        if let notice = Hotkey.statusText(for: hotkey) { panel.note(notice) }
        self.panel = panel
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

    /// The gear's Settings… item, reached through the responder chain.
    @objc
    internal func showSettings(_ sender: Any?) {
        let text = Hotkey.statusText(for: hotkey) ?? "\(Hotkey.displayName) is registered."
        let window = settings ?? SettingsWindow(text: text)
        settings = window
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
