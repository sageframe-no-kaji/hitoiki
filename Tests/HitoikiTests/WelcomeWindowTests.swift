import AppKit
import Carbon.HIToolbox
import Foundation
import Testing

@testable import Hitoiki

/// A launch as the welcome sees it: an app over a fixture's store and history, and the fixture's panel.
///
/// Open Hitoiki shows that panel. Nothing here registers a hotkey or reaches the user's own defaults.
@MainActor
private struct Launch {
    let fixture: Fixture
    let app: HitoikiApp

    init() throws {
        fixture = try Fixture()
        app = HitoikiApp(settings: fixture.settings, history: fixture.history)
    }

    var settings: Settings { fixture.settings }
    var suite: ThrowawaySuite { fixture.suite }

    /// The launch's welcome step, with the launch's registration `status` and login mark.
    func welcome(atLogin: Bool = false, status: OSStatus = noErr) {
        app.welcome(atLogin: atLogin, status: status, panel: fixture.panel)
    }

    /// The welcome window this launch showed, failing the test when there is none.
    func window() throws -> WelcomeWindow {
        let window = try #require(app.welcomeWindow)
        #expect(window.isVisible)
        return window
    }

    func tearDown() {
        app.welcomeWindow?.orderOut(nil)
        app.settingsWindow?.orderOut(nil)
        app.aboutWindow?.orderOut(nil)
        fixture.tearDown()
    }
}

/// The welcome windows on screen in this process.
@MainActor
private func welcomeWindowsShown() -> Int {
    NSApplication.shared.windows.filter { $0 is WelcomeWindow && $0.isVisible }.count
}

/// An `aevt` event with `id`, carrying `mark` as its `keyAEPropData` enumeration when there is one.
private func appleEvent(_ id: AEEventID, mark: AEKeyword?) -> NSAppleEventDescriptor {
    let event = NSAppleEventDescriptor.appleEvent(
        withEventClass: AEEventClass(kCoreEventClass),
        eventID: id,
        targetDescriptor: nil,
        returnID: AEReturnID(kAutoGenerateReturnID),
        transactionID: AETransactionID(kAnyTransactionID))
    if let mark {
        event.setParam(NSAppleEventDescriptor(enumCode: mark), forKeyword: AEKeyword(keyAEPropData))
    }
    return event
}

/// The window's lines of text, from the top.
@MainActor
private func lines(in window: NSWindow) -> [String] {
    labels(in: window).map(\.stringValue)
}

/// The window's text fields, from the top, once laid out.
@MainActor
private func labels(in window: NSWindow) -> [NSTextField] {
    window.contentView?.layoutSubtreeIfNeeded()
    // Window coordinates rise upward: the first line is the highest.
    return descendants(of: window.contentView).compactMap { $0 as? NSTextField }
        .sorted { $0.convert($0.bounds, to: nil).minY > $1.convert($1.bounds, to: nil).minY }
}

/// The window's buttons, from the left.
@MainActor
private func buttons(in window: NSWindow) -> [NSButton] {
    window.contentView?.layoutSubtreeIfNeeded()
    return descendants(of: window.contentView).compactMap { $0 as? NSButton }
        .sorted { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
}

/// Every view under `view`, depth first.
@MainActor
private func descendants(of view: NSView?) -> [NSView] {
    guard let view else { return [] }
    return view.subviews + view.subviews.flatMap { descendants(of: $0) }
}

/// Presses `button` as a click does, without the run-loop spin of `performClick`.
@MainActor
private func click(_ button: NSButton) {
    #expect(button.sendAction(button.action, to: button.target))
}

/// The Escape key going down in `window`.
@MainActor
private func escape(in window: NSWindow) throws -> NSEvent {
    try #require(
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            isARepeat: false,
            keyCode: UInt16(kVK_Escape)))
}

/// Option-Command-Space: a recorded shortcut, named the same under every keyboard layout.
private let optionCommandSpace = Shortcut.Combination(keyCode: 49, modifiers: 2_048 + 256)

/// A status the registration returns when the combination is already held.
private let taken = OSStatus(eventHotKeyExistsErr)

private let menuBarOn = "Hitoiki has no Dock icon. Its icon is in the menu bar, and you can turn that off in Settings."
private let menuBarOff = "Hitoiki has no Dock icon. You can show its icon in the menu bar from Settings."
private let settingsLine = "In the panel, ⌘, (Command-comma) opens Settings."

// Nested in the Panel suite so its tests run one at a time with the Panel suite's: the welcome window takes the
// keyboard, and Open Hitoiki shows a panel.
extension PanelTests {
    @Suite("Welcome window")
    @MainActor
    internal struct WelcomeWindowTests {
        // Once (Decisions 2 and 3).

        @Test("Once: the key absent or stored false, a launch not at login shows the window and writes the key true")
        internal func firstLaunch() throws {
            for storedFalse in [false, true] {
                let launch = try Launch()
                defer { launch.tearDown() }
                if storedFalse { launch.suite.defaults.set(false, forKey: "welcomeShown") }
                let before = launch.suite.keys
                launch.welcome()
                let window = try launch.window()
                #expect(window.title == "Welcome to Hitoiki")
                #expect(welcomeWindowsShown() == 1)
                #expect(launch.suite.defaults.object(forKey: "welcomeShown") as? Bool == true)
                // The one key the welcome writes.
                #expect(launch.suite.keys == before.union(["welcomeShown"]))
                // Nothing else is shown.
                #expect(!launch.fixture.window.isVisible)
                #expect(launch.app.settingsWindow == nil)

                // Quit with the window still open: the next launch over the same store shows nothing.
                let next = HitoikiApp(settings: launch.settings, history: launch.fixture.history)
                next.welcome(atLogin: false, status: noErr, panel: launch.fixture.panel)
                #expect(next.welcomeWindow == nil)
            }
        }

        @Test("Once: the key absent, a login-item launch shows nothing and writes the key true")
        internal func firstLaunchAtLogin() throws {
            let launch = try Launch()
            defer { launch.tearDown() }
            let before = launch.suite.keys
            launch.welcome(atLogin: true)
            #expect(launch.app.welcomeWindow == nil)
            #expect(welcomeWindowsShown() == 0)
            #expect(launch.suite.defaults.object(forKey: "welcomeShown") as? Bool == true)
            #expect(launch.suite.keys == before.union(["welcomeShown"]))
            #expect(!launch.fixture.window.isVisible)
        }

        @Test("Once: the key true, a launch at login or not shows nothing and leaves the key as it was")
        internal func laterLaunches() throws {
            for atLogin in [false, true] {
                let launch = try Launch()
                defer { launch.tearDown() }
                launch.suite.defaults.set(true, forKey: "welcomeShown")
                let before = launch.suite.keys
                launch.welcome(atLogin: atLogin)
                #expect(launch.app.welcomeWindow == nil)
                #expect(welcomeWindowsShown() == 0)
                #expect(launch.suite.defaults.object(forKey: "welcomeShown") as? Bool == true)
                #expect(launch.suite.keys == before)
                #expect(!launch.fixture.window.isVisible)
            }
        }

        @Test("No other path shows the window: settings, About, Check for Updates and reopen leave it unshown")
        internal func noOtherPath() throws {
            let launch = try Launch()
            defer { launch.tearDown() }
            let app = launch.app
            app.showSettings(nil)
            app.showAbout(nil)
            app.checkForUpdates(nil)
            #expect(!app.applicationShouldHandleReopen(NSApplication.shared, hasVisibleWindows: false))
            #expect(app.welcomeWindow == nil)
            #expect(welcomeWindowsShown() == 0)
            // Nor did any of them write the key.
            #expect(launch.suite.defaults.object(forKey: "welcomeShown") == nil)
        }

        @Test("The login-item mark is read from the open-application event's keyAEPropData, and only there")
        internal func loginMark() {
            let login = keyAELaunchedAsLogInItem
            #expect(HitoikiApp.launchedAtLogin(appleEvent(kAEOpenApplication, mark: login)))
            #expect(!HitoikiApp.launchedAtLogin(appleEvent(kAEOpenApplication, mark: nil)))
            #expect(!HitoikiApp.launchedAtLogin(appleEvent(kAEOpenApplication, mark: keyAELaunchedAsServiceItem)))
            #expect(!HitoikiApp.launchedAtLogin(appleEvent(kAEReopenApplication, mark: login)))
            #expect(!HitoikiApp.launchedAtLogin(nil))
        }

        // The text (Decision 1).

        @Test("Registered, the default: the symbols line and the spelled-out line; Open Hitoiki alone, the default")
        internal func registeredDefault() throws {
            let launch = try Launch()
            defer { launch.tearDown() }
            launch.welcome()
            let window = try launch.window()
            #expect(
                lines(in: window) == [
                    "Hitoiki is running", "Press ⌃⌘Space to open it from any app.", "(Control-Command-Space)",
                    menuBarOn, settingsLine,
                ])
            // The symbols in the accent colour, the words around them in ink.
            let press = try #require(labels(in: window).first { $0.stringValue.hasPrefix("Press") })
            let text = press.attributedStringValue
            #expect(same(text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, Theme.Token.ink))
            #expect(
                same(text.attribute(.foregroundColor, at: 6, effectiveRange: nil) as? NSColor, Theme.Token.accent))
            #expect(buttons(in: window).map(\.title) == ["Open Hitoiki"])
            #expect(window.openButton.keyEquivalent == "\r")
            #expect(window.changeButton == nil)
            // Built as About is: 360 points wide, the title bar transparent, movable by its background.
            #expect(window.contentRect(forFrameRect: window.frame).width == 360)
            #expect(window.titlebarAppearsTransparent)
            #expect(window.isMovableByWindowBackground)
        }

        @Test("Registered, a recorded shortcut: its symbols line alone")
        internal func registeredRecorded() throws {
            let launch = try Launch()
            defer { launch.tearDown() }
            launch.settings.shortcut = optionCommandSpace
            launch.welcome()
            let window = try launch.window()
            #expect(
                lines(in: window) == [
                    "Hitoiki is running", "Press ⌥⌘Space to open it from any app.", menuBarOn, settingsLine,
                ])
            #expect(buttons(in: window).map(\.title) == ["Open Hitoiki"])
        }

        @Test("Not registered: the failure line naming the attempted combination; both buttons, Change the default")
        internal func notRegistered() throws {
            for (recorded, symbols) in [(false, "⌃⌘Space"), (true, "⌥⌘Space")] {
                let launch = try Launch()
                defer { launch.tearDown() }
                if recorded { launch.settings.shortcut = optionCommandSpace }
                launch.welcome(status: taken)
                let window = try launch.window()
                #expect(
                    lines(in: window) == [
                        "Hitoiki is running",
                        "\(symbols) couldn't be set up. Another app or macOS may already be using it.",
                        menuBarOn, settingsLine,
                    ])
                #expect(buttons(in: window).map(\.title) == ["Open Hitoiki", "Change the Shortcut"])
                let change = try #require(window.changeButton)
                #expect(change.keyEquivalent == "\r")
                #expect(window.openButton.keyEquivalent.isEmpty)
            }
        }

        @Test("The menu bar line: on, its icon is there and can be turned off; off, it can be shown from Settings")
        internal func menuBarLine() throws {
            for shown in [true, false] {
                let launch = try Launch()
                defer { launch.tearDown() }
                launch.settings.menuBarEnabled = shown
                launch.welcome()
                let window = try launch.window()
                let text = lines(in: window)
                #expect(text.contains(shown ? menuBarOn : menuBarOff))
                #expect(!text.contains(shown ? menuBarOff : menuBarOn))
            }
        }

        // The buttons (Decision 1).

        @Test("Open Hitoiki closes the window and shows the panel; settings stays unopened")
        internal func openHitoiki() throws {
            for status in [noErr, taken] {
                let launch = try Launch()
                defer { launch.tearDown() }
                launch.welcome(status: status)
                let window = try launch.window()
                click(window.openButton)
                #expect(!window.isVisible)
                #expect(launch.fixture.window.isVisible)
                #expect(launch.app.settingsWindow == nil)
            }
        }

        @Test(
            "Change the Shortcut closes the window and opens settings as the menu bar item does; the panel stays hidden"
        )
        internal func changeTheShortcut() throws {
            let launch = try Launch()
            defer { launch.tearDown() }
            launch.welcome(status: taken)
            let window = try launch.window()
            click(try #require(window.changeButton))
            #expect(!window.isVisible)
            let settings = try #require(launch.app.settingsWindow)
            #expect(settings.isVisible)
            // Opened from no panel, so closing it shows nothing.
            #expect(settings.origin == nil)
            #expect(!launch.fixture.window.isVisible)
        }

        @Test("Escape and the close button close the window and show neither the panel nor settings")
        internal func escapeAndClose() throws {
            for byEscape in [true, false] {
                let launch = try Launch()
                defer { launch.tearDown() }
                launch.welcome(status: taken)
                let window = try launch.window()
                if byEscape {
                    window.sendEvent(try escape(in: window))
                } else {
                    // What the close button sends.
                    window.performClose(nil)
                }
                #expect(!window.isVisible)
                #expect(!launch.fixture.window.isVisible)
                #expect(launch.app.settingsWindow == nil)
            }
        }
    }
}
