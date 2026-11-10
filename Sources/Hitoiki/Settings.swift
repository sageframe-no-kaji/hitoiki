import AppKit
import Carbon.HIToolbox
import Observation

/// One macro slot: a label for the user, shown only in settings, and the command Command-N loads.
internal struct Macro: Equatable, Sendable {
    internal var name = ""
    internal var command = ""
}

/// Where commands start: the user's home, or a folder the user picked.
internal enum DirectoryMode: String, Sendable {
    case home
    case fixed
}

/// The appearance override (System Design §2.4, amended 2026-11-09).
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

/// Everything Hitoiki keeps: ten keys in one user-defaults domain, read and written in place.
///
/// The store holds no copy of any value; every read goes to the defaults and every write goes to them, and
/// an absent key reads as its default, so a fresh install writes nothing until the user changes something.
/// Observable, so the settings form binds to it and the live effects follow a change.
@MainActor
@Observable
internal final class Settings {
    /// The ten keys of ho-05.1 Decision 1, and no other.
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
    }

    /// Control-Command-Space.
    internal static let defaultShortcut = Shortcut.Combination(
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

    /// The history switch; ho-05.2 reads it.
    internal var historyEnabled: Bool {
        get {
            access(keyPath: \.historyEnabled)
            return bool(.historyEnabled, absent: false)
        }
        set { withMutation(keyPath: \.historyEnabled) { defaults.set(newValue, forKey: Key.historyEnabled.rawValue) } }
    }

    /// The menu bar item switch.
    internal var menuBarEnabled: Bool {
        get {
            access(keyPath: \.menuBarEnabled)
            return bool(.menuBarEnabled, absent: false)
        }
        set { withMutation(keyPath: \.menuBarEnabled) { defaults.set(newValue, forKey: Key.menuBarEnabled.rawValue) } }
    }

    /// The automatic update check's switch, on when its key is absent (replan ruling 5); ho-06 reads it.
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

    /// The nine slots, always nine: missing slots read empty, and only nine are written.
    internal var macros: [Macro] {
        get {
            access(keyPath: \.macros)
            let stored = defaults.array(forKey: Key.macros.rawValue) as? [[String: String]] ?? []
            let slots = stored.prefix(Self.macroSlots).map {
                Macro(name: $0["name"] ?? "", command: $0["command"] ?? "")
            }
            return slots + Array(repeating: Macro(), count: Self.macroSlots - slots.count)
        }
        set {
            withMutation(keyPath: \.macros) {
                let slots =
                    newValue.prefix(Self.macroSlots)
                    + Array(repeating: Macro(), count: max(0, Self.macroSlots - newValue.count))
                defaults.set(slots.map { ["name": $0.name, "command": $0.command] }, forKey: Key.macros.rawValue)
            }
        }
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

    /// Writes `value`, or removes the key for nil.
    private func store(_ value: String?, _ key: Key) {
        if let value {
            defaults.set(value, forKey: key.rawValue)
        } else {
            defaults.removeObject(forKey: key.rawValue)
        }
    }
}
