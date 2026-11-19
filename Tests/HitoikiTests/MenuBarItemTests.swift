import AppKit
import Carbon.HIToolbox
import Testing

@testable import Hitoiki

/// The status-bar windows this process has on screen: one per status item in the menu bar.
@MainActor
private func statusWindows() -> Int {
    NSApplication.shared.windows.filter { $0.className.contains("StatusBarWindow") && $0.isVisible }.count
}

/// How many times Show Hitoiki was chosen.
@MainActor
private final class Shown {
    var count = 0
}

// Serialized: the status-bar window count is this suite's alone only while one of its tests runs.
@Suite("Menu bar item", .serialized)
@MainActor
internal struct MenuBarItemTests {
    @Test("The item exists exactly while the setting reads true: on, off, on, one item at a time")
    internal func followsSetting() async throws {
        let suite = try ThrowawaySuite()
        defer { suite.remove() }
        let settings = Settings(defaults: suite.defaults)
        let menuBar = MenuBarItem {}
        defer { menuBar.isShown = false }
        let before = statusWindows()
        // The key is absent, so the setting reads on and the item is made at once.
        settings.follow({ $0.menuBarEnabled }, apply: { menuBar.isShown = $0 })
        let first = try #require(menuBar.item)
        #expect(first.menu === menuBar.menu)
        #expect(first.button?.image === MenuBarItem.image)
        try await until { statusWindows() == before + 1 }

        settings.menuBarEnabled = false
        try await until { menuBar.item == nil }
        try await until { statusWindows() == before }

        settings.menuBarEnabled = true
        try await until { menuBar.item != nil }
        #expect(menuBar.item !== first)
        try await until { statusWindows() == before + 1 }
        settings.menuBarEnabled = true
        menuBar.isShown = true
        #expect(statusWindows() == before + 1)
    }

    @Test("A store that reads on at launch makes the item at once")
    internal func onAtLaunch() throws {
        let suite = try ThrowawaySuite()
        defer { suite.remove() }
        suite.defaults.set(true, forKey: "menuBarEnabled")
        let menuBar = MenuBarItem {}
        defer { menuBar.isShown = false }
        Settings(defaults: suite.defaults).follow({ $0.menuBarEnabled }, apply: { menuBar.isShown = $0 })
        #expect(menuBar.item != nil)
    }

    @Test("The menu: Show Hitoiki; About Hitoiki, Check for Updates…, Settings…; Quit; in order, with actions")
    internal func menu() {
        let shown = Shown()
        let menuBar = MenuBarItem { shown.count += 1 }
        let titles = menuBar.menu.items.map { $0.isSeparatorItem ? "—" : $0.title }
        #expect(
            titles == ["Show Hitoiki", "—", "About Hitoiki", "Check for Updates…", "Settings…", "—", "Quit"])
        let items = menuBar.menu.items
        #expect(items[2].action == #selector(HitoikiApp.showAbout(_:)))
        #expect(items[3].action == #selector(HitoikiApp.checkForUpdates(_:)))
        #expect(items[4].action == #selector(HitoikiApp.showSettings(_:)))
        #expect(items[6].action == #selector(NSApplication.terminate(_:)))
        // About, Check for Updates… and Settings… have no target: each climbs the responder chain to the
        // application's delegate, which answers it.
        for item in items[2...4] {
            #expect(item.target == nil)
            #expect(HitoikiApp.instancesRespond(to: item.action))
        }
        menuBar.menu.performActionForItem(at: 0)
        #expect(shown.count == 1)
    }

    @Test("Show Hitoiki's key equivalent is the registered shortcut's, read as the menu opens")
    internal func keyEquivalent() {
        let menuBar = MenuBarItem {}
        let show = menuBar.menu.items[0]
        let all = UInt32(controlKey | optionKey | shiftKey | cmdKey)
        #expect(
            Hotkey.register(keyCode: UInt32(kVK_ANSI_H), modifiers: UInt32(controlKey | optionKey | cmdKey)) {} == noErr
        )
        defer { Hotkey.unregister() }
        menuBar.menuNeedsUpdate(menuBar.menu)
        #expect(show.keyEquivalent == "h")
        #expect(show.keyEquivalentModifierMask == [.control, .option, .command])

        #expect(Hotkey.replace(keyCode: UInt32(kVK_F5), modifiers: all) == noErr)
        menuBar.menuNeedsUpdate(menuBar.menu)
        #expect(show.keyEquivalent == "\u{F708}")
        #expect(show.keyEquivalentModifierMask == [.control, .option, .shift, .command])

        Hotkey.unregister()
        menuBar.menuNeedsUpdate(menuBar.menu)
        #expect(show.keyEquivalent.isEmpty)
    }

    @Test("Discovery: the glyph loads from the SVG as a template image, 18 points across, ink on no ground")
    internal func glyph() throws {
        let image = try #require(MenuBarItem.image)
        #expect(image.isTemplate)
        #expect(max(image.size.width, image.size.height) == 18)
        #expect(image.size.width > image.size.height)
        let width = 72
        let height = Int((Double(width) * image.size.height / image.size.width).rounded(.up))
        let bitmap = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        var inked = 0
        for y in 0..<height {
            for x in 0..<width where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                inked += 1
            }
        }
        // Ink, and ground left bare: the two shapes cover some of the box and not all of it.
        #expect(inked > width * height / 10)
        #expect(inked < width * height * 9 / 10)
        // The corners are ground: the top-left and bottom-right of the box hold neither shape.
        #expect((bitmap.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.5)
        #expect((bitmap.colorAt(x: width - 1, y: height - 1)?.alphaComponent ?? 1) < 0.5)
    }
}
