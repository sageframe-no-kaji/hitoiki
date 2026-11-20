import AppKit
import Carbon.HIToolbox
import Observation

/// Where commands start: the user's home, or a folder the user picked.
internal enum DirectoryMode: String, Sendable {
    case home
    case fixed
}

/// The appearance: the system's, or always light, or always dark.
internal enum Appearance: String, Sendable, CaseIterable {
    case system
    case light
    case dark

    /// What `NSApp.appearance` is set to; nil follows the system.
    ///
    /// Every colour token carries a light and a dark value, so the one assignment turns the panel, the
    /// settings window and the menu bar item together.
    @MainActor internal var nsAppearance: NSAppearance? {
        switch self {
        case .system:
            nil
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        }
    }
}

/// The settings, the macros and the welcome window's mark: eleven keys in one user-defaults domain, read and
/// written in place.
///
/// The store holds no copy of any value; every read goes to the defaults and every write goes to them, and
/// an absent key reads as its default, so a fresh install writes nothing until the user changes something,
/// except the welcome window's mark, which the first launch writes.
/// Observable, so the settings form binds to it and the live effects follow a change.
@MainActor
@Observable
internal final class Settings {
    /// The eleven keys the store writes, and no other.
    internal enum Key: String, CaseIterable, Sendable {
        case shortcutKeyCode
        case shortcutModifiers
        case directoryMode
        case directoryPath
        case terminal
        case appearance
        case historyEnabled
        case menuBarEnabled
        case updateCheckEnabled
        case macros
        case welcomeShown
    }

    /// Control-Command-Space.
    ///
    /// Nonisolated, a constant of a Sendable type: the recorder's verdict, which runs off the main actor,
    /// exempts it from the system-list check (ho-05.1 Decision 14).
    nonisolated internal static let defaultShortcut = Shortcut.Combination(
        keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | cmdKey))
    /// Terminal.app, which every Mac has.
    internal static let defaultTerminal = "com.apple.Terminal"
    /// Command-1 through Command-9.
    internal static let macroSlots = 9

    private let defaults: UserDefaults

    /// A store over `defaults`: `UserDefaults.standard` in the app, a throwaway suite in a test.
    internal init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The global shortcut; written by the recorder only once the combination is registered.
    internal var shortcut: Shortcut.Combination {
        get {
            access(keyPath: \.shortcut)
            let fallback = Self.defaultShortcut
            return Shortcut.Combination(
                keyCode: (number(.shortcutKeyCode)?.uint32Value) ?? fallback.keyCode,
                modifiers: (number(.shortcutModifiers)?.uint32Value) ?? fallback.modifiers)
        }
        set {
            withMutation(keyPath: \.shortcut) {
                defaults.set(Int(newValue.keyCode), forKey: Key.shortcutKeyCode.rawValue)
                defaults.set(Int(newValue.modifiers), forKey: Key.shortcutModifiers.rawValue)
            }
        }
    }

    /// Home, or the fixed folder in `directoryPath`.
    internal var directoryMode: DirectoryMode {
        get {
            access(keyPath: \.directoryMode)
            return string(.directoryMode).flatMap(DirectoryMode.init(rawValue:)) ?? .home
        }
        set { withMutation(keyPath: \.directoryMode) { store(newValue.rawValue, .directoryMode) } }
    }

    /// The folder the user picked; kept when the mode goes back to home, so the picker still offers it.
    internal var directoryPath: String? {
        get {
            access(keyPath: \.directoryPath)
            return string(.directoryPath)
        }
        set { withMutation(keyPath: \.directoryPath) { store(newValue, .directoryPath) } }
    }

    /// The bundle identifier Open in Terminal hands the folder to.
    internal var terminal: String {
        get {
            access(keyPath: \.terminal)
            return string(.terminal) ?? Self.defaultTerminal
        }
        set { withMutation(keyPath: \.terminal) { store(newValue, .terminal) } }
    }

    /// System, light or dark.
    internal var appearance: Appearance {
        get {
            access(keyPath: \.appearance)
            return string(.appearance).flatMap(Appearance.init(rawValue:)) ?? .system
        }
        set { withMutation(keyPath: \.appearance) { store(newValue.rawValue, .appearance) } }
    }

    /// The history switch.
    internal var historyEnabled: Bool {
        get {
            access(keyPath: \.historyEnabled)
            return bool(.historyEnabled, absent: false)
        }
        set { withMutation(keyPath: \.historyEnabled) { defaults.set(newValue, forKey: Key.historyEnabled.rawValue) } }
    }

    /// The menu bar item switch, on when its key is absent; a stored false stays off.
    internal var menuBarEnabled: Bool {
        get {
            access(keyPath: \.menuBarEnabled)
            return bool(.menuBarEnabled, absent: true)
        }
        set { withMutation(keyPath: \.menuBarEnabled) { defaults.set(newValue, forKey: Key.menuBarEnabled.rawValue) } }
    }

    /// The automatic update check's switch, on when its key is absent.
    internal var updateCheckEnabled: Bool {
        get {
            access(keyPath: \.updateCheckEnabled)
            return bool(.updateCheckEnabled, absent: true)
        }
        set {
            withMutation(keyPath: \.updateCheckEnabled) {
                defaults.set(newValue, forKey: Key.updateCheckEnabled.rawValue)
            }
        }
    }

    /// The nine slots, always nine, each a command or empty.
    ///
    /// Stored as an array of nine strings. Missing slots read empty, and only nine are written; an entry that is
    /// not a string, as an older shape of this setting may hold, reads as an empty slot in its place.
    internal var macros: [String] {
        get {
            access(keyPath: \.macros)
            let stored = (defaults.array(forKey: Key.macros.rawValue) ?? []).prefix(Self.macroSlots)
            let slots = stored.map { $0 as? String ?? "" }
            return slots + Array(repeating: "", count: Self.macroSlots - slots.count)
        }
        set {
            withMutation(keyPath: \.macros) {
                let slots =
                    newValue.prefix(Self.macroSlots)
                    + Array(repeating: "", count: max(0, Self.macroSlots - newValue.count))
                defaults.set(Array(slots), forKey: Key.macros.rawValue)
            }
        }
    }

    /// Whether the welcome window has had its one showing, false when its key is absent.
    ///
    /// The launch writes it true as the window shows, or as a login-item launch passes the window by; nothing
    /// writes it false.
    internal var welcomeShown: Bool {
        get {
            access(keyPath: \.welcomeShown)
            return bool(.welcomeShown, absent: false)
        }
        set { withMutation(keyPath: \.welcomeShown) { defaults.set(newValue, forKey: Key.welcomeShown.rawValue) } }
    }

    /// Calls `apply` with what `read` returns now, and again with what it returns after each change to the
    /// settings it read: how a live effect follows the store without a second channel.
    ///
    /// Observation reports a change before it is written, so the new value is read on the main actor's
    /// next turn.
    internal func follow<Value>(
        _ read: @escaping @MainActor @Sendable (Settings) -> Value,
        apply: @escaping @MainActor @Sendable (Value) -> Void
    ) {
        let value = withObservationTracking {
            read(self)
        } onChange: { [weak self] in
            Task { @MainActor in self?.follow(read, apply: apply) }
        }
        apply(value)
    }

    private func number(_ key: Key) -> NSNumber? {
        defaults.object(forKey: key.rawValue) as? NSNumber
    }

    private func string(_ key: Key) -> String? {
        defaults.string(forKey: key.rawValue)
    }

    private func bool(_ key: Key, absent: Bool) -> Bool {
        number(key)?.boolValue ?? absent
    }

    /// Nil removes the key rather than storing an empty string, so an absent value reads as the default.
    private func store(_ value: String?, _ key: Key) {
        if let value {
            defaults.set(value, forKey: key.rawValue)
        } else {
            defaults.removeObject(forKey: key.rawValue)
        }
    }
}
