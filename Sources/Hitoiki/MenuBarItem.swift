import AppKit

/// The menu bar item, there exactly while its setting is on: the app icon's two ink shapes as a template
/// image, and its menu.
@MainActor
internal final class MenuBarItem: NSObject, NSMenuDelegate {
    /// The glyph: the breath and the chevron on no ground, so the menu bar tints it for light and dark.
    internal static let image: NSImage? = {
        guard let url = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "svg", subdirectory: "Resources"),
            let image = NSImage(contentsOf: url)
        else { return nil }
        image.isTemplate = true
        // Fitted to the 18-point square the menu bar draws a template image in.
        let scale = 18 / max(image.size.width, image.size.height, 1)
        image.size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        image.accessibilityDescription = "Hitoiki"
        return image
    }()

    /// The item while it is in the menu bar.
    internal private(set) var item: NSStatusItem?
    /// Show Hitoiki; About Hitoiki, Hitoiki Help, Check for Updates… and Settings…; Quit, in three groups.
    internal let menu = NSMenu()

    private let show: @MainActor () -> Void
    private let showItem: NSMenuItem

    /// A menu whose Show Hitoiki calls `show`.
    ///
    /// About Hitoiki, Hitoiki Help, Check for Updates… and Settings… go up the responder chain to the
    /// application's delegate, as the gear's click does; Quit ends the app as Command-Q does.
    internal init(show: @escaping @MainActor () -> Void) {
        self.show = show
        showItem = NSMenuItem(title: "Show Hitoiki", action: nil, keyEquivalent: "")
        super.init()
        showItem.action = #selector(showPressed)
        showItem.target = self
        menu.addItem(showItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "About Hitoiki", action: #selector(HitoikiApp.showAbout(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Hitoiki Help", action: #selector(HitoikiApp.showHelp(_:)), keyEquivalent: "")
        menu.addItem(
            withTitle: "Check for Updates…", action: #selector(HitoikiApp.checkForUpdates(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(HitoikiApp.showSettings(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        menu.delegate = self
    }

    /// True while the item is in the menu bar; a change acts at once, so the switch needs no relaunch.
    internal var isShown: Bool {
        get { item != nil }
        set {
            if newValue, item == nil {
                let made = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                made.button?.image = Self.image
                made.menu = menu
                item = made
            } else if !newValue, let item {
                NSStatusBar.system.removeStatusItem(item)
                self.item = nil
            }
        }
    }

    /// Shows the registered shortcut as Show Hitoiki's key equivalent, read as the menu opens.
    internal func menuNeedsUpdate(_ menu: NSMenu) {
        guard let shortcut = Hotkey.registered else {
            showItem.keyEquivalent = ""
            return
        }
        showItem.keyEquivalent = Shortcut.keyEquivalent(shortcut.keyCode)
        showItem.keyEquivalentModifierMask = Shortcut.eventModifiers(shortcut.modifiers)
    }

    @objc
    private func showPressed() {
        show()
    }
}
