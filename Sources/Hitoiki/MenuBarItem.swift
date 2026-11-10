import AppKit

/// The menu bar item, there exactly while its setting is on: the app icon's two ink shapes as a template
/// image, and a menu of Show Hitoiki, Settings… and Quit.
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
    /// Show Hitoiki, Settings… and Quit.
    internal let menu = NSMenu()

    private let show: @MainActor () -> Void
    private let showItem: NSMenuItem

    /// A menu whose Show Hitoiki calls `show`; Settings… opens the settings window and Quit ends the app, as the
    /// gear's click and settings' Quit do.
    internal init(show: @escaping @MainActor () -> Void) {
        self.show = show
        showItem = NSMenuItem(title: "Show Hitoiki", action: nil, keyEquivalent: "")
        super.init()
        showItem.action = #selector(showPressed)
        showItem.target = self
        menu.addItem(showItem)
        menu.addItem(withTitle: "Settings…", action: #selector(HitoikiApp.showSettings(_:)), keyEquivalent: "")
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
