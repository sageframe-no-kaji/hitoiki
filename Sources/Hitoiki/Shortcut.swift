import AppKit
import Carbon.HIToolbox

/// The global shortcut as the recorder sees it: a key and its modifiers, the checks a candidate must pass
/// before it is tried, and the name settings and the menu show for it.
///
/// The verdict is a pure function of the candidate and the system's list, so tests feed it lists.
internal enum Shortcut {
    /// A key and its modifiers, as Carbon's hotkey registration takes them.
    internal struct Combination: Hashable, Sendable {
        /// A Carbon virtual key code (`kVK_…`).
        internal let keyCode: UInt32
        /// A Carbon modifier mask: `controlKey`, `optionKey`, `shiftKey` and `cmdKey` only.
        internal let modifiers: UInt32
    }

    /// One system-wide shortcut as macOS reports it.
    internal struct SystemShortcut: Sendable, Equatable {
        internal let combination: Combination
        internal let enabled: Bool
    }

    /// Why a candidate is refused before it is tried.
    internal enum Refusal: Sendable, Equatable {
        /// Modifiers alone, or modifiers released with no key pressed.
        case noKey
        /// Neither Command, Control nor Option, and not a function key.
        case noQualifyingModifier
        /// An enabled system shortcut has it.
        case takenByMacOS

        /// The line under the recorder.
        internal var message: String {
            switch self {
            case .noKey, .noQualifyingModifier:
                "Press a key with Command, Control or Option."
            case .takenByMacOS:
                "Taken by macOS."
            }
        }
    }

    /// What the recorder does with a candidate: try to register it, or refuse it and say why.
    internal enum Verdict: Sendable, Equatable {
        case allowed(Combination)
        case refused(Refusal)
    }

    /// The four modifiers a hotkey carries; every other bit (Caps Lock, the function key) is dropped.
    internal static let modifierMask = UInt32(controlKey | optionKey | shiftKey | cmdKey)

    /// Command, Control or Option: one must be held, unless the key is a function key.
    private static let qualifying = UInt32(cmdKey | controlKey | optionKey)

    /// The key codes of the modifier keys themselves, which are not keys a shortcut can end on.
    private static let modifierKeys: Set<UInt32> = Set(
        [
            kVK_Command, kVK_RightCommand, kVK_Shift, kVK_RightShift, kVK_Option, kVK_RightOption,
            kVK_Control, kVK_RightControl, kVK_CapsLock, kVK_Function,
        ].map(UInt32.init))

    /// A key with a name and no character of its own: what settings calls it, what a menu takes as its key
    /// equivalent, and whether it may stand without a modifier.
    private struct NamedKey {
        let name: String
        let equivalent: Character
        var standsAlone = false
    }

    // The one list in this file. These keys type no character, or one that is not their name, so
    // `UCKeyTranslate` cannot name them; the function keys are also the keys check 2 lets stand alone, as
    // macOS's own shortcut settings do.
    private static let named: [UInt32: NamedKey] = {
        var keys: [Int: NamedKey] = [
            kVK_Space: NamedKey(name: "Space", equivalent: " "),
            kVK_Return: NamedKey(name: "Return", equivalent: "\r"),
            kVK_Tab: NamedKey(name: "Tab", equivalent: "\t"),
            kVK_Escape: NamedKey(name: "Escape", equivalent: "\u{1B}"),
            kVK_Delete: NamedKey(name: "Delete", equivalent: "\u{08}"),
            kVK_ForwardDelete: NamedKey(name: "Forward Delete", equivalent: Self.function(NSDeleteFunctionKey)),
            kVK_Home: NamedKey(name: "Home", equivalent: Self.function(NSHomeFunctionKey)),
            kVK_End: NamedKey(name: "End", equivalent: Self.function(NSEndFunctionKey)),
            kVK_PageUp: NamedKey(name: "Page Up", equivalent: Self.function(NSPageUpFunctionKey)),
            kVK_PageDown: NamedKey(name: "Page Down", equivalent: Self.function(NSPageDownFunctionKey)),
            kVK_LeftArrow: NamedKey(name: "Left Arrow", equivalent: Self.function(NSLeftArrowFunctionKey)),
            kVK_RightArrow: NamedKey(name: "Right Arrow", equivalent: Self.function(NSRightArrowFunctionKey)),
            kVK_UpArrow: NamedKey(name: "Up Arrow", equivalent: Self.function(NSUpArrowFunctionKey)),
            kVK_DownArrow: NamedKey(name: "Down Arrow", equivalent: Self.function(NSDownArrowFunctionKey)),
        ]
        let functionKeys = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
            kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19,
        ]
        for (index, code) in functionKeys.enumerated() {
            keys[code] = NamedKey(
                name: "F\(index + 1)", equivalent: Self.function(NSF1FunctionKey + index), standsAlone: true)
        }
        return Dictionary(uniqueKeysWithValues: keys.map { (UInt32($0.key), $0.value) })
    }()

    /// Checks 1 to 3 of the recorder's four, in order; check 4 is the registration itself.
    ///
    /// The default, `Settings.defaultShortcut`, is exempt from check 3.
    ///
    /// - Parameters:
    ///   - keyCode: The key pressed, or nil when modifiers were pressed and released with no key.
    ///   - modifiers: The Carbon modifiers held with it.
    ///   - system: The system's shortcuts, as `systemShortcuts()` reads them.
    /// - Returns: The combination to try, or the refusal.
    internal static func verdict(keyCode: UInt32?, modifiers: UInt32, system: [SystemShortcut]) -> Verdict {
        guard let keyCode, !modifierKeys.contains(keyCode) else { return .refused(.noKey) }
        let held = modifiers & modifierMask
        if held & qualifying == 0, named[keyCode]?.standsAlone != true {
            return .refused(.noQualifyingModifier)
        }
        let candidate = Combination(keyCode: keyCode, modifiers: held)
        // The app's own default passes check 3 whatever the list says: the list reports Control-Command-Space
        // enabled (the Character Viewer) on Macs whose System Settings show no such item, and the default was
        // chosen knowing the collision. Checks 1 and 2 above still apply to it, and check 4, the registration,
        // still refuses it where macOS really holds it (ho-05.1 Decision 14).
        if candidate == Settings.defaultShortcut { return .allowed(candidate) }
        // The system's list reports the app switcher, Command-Tab and Shift-Command-Tab, with the rest, so no
        // combination is refused by name (ho-05.1 Decision 4).
        let taken = system.contains { $0.enabled && $0.combination == candidate }
        return taken ? .refused(.takenByMacOS) : .allowed(candidate)
    }

    /// Every system-wide shortcut macOS has, enabled or not, asked of the system each time.
    internal static func systemShortcuts() -> [SystemShortcut] {
        var listed: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&listed) == noErr, let array = listed?.takeRetainedValue(),
            let entries = (array as NSArray) as? [[String: Any]]
        else { return [] }
        // The dictionary keys are CFSTR macros in the header, which Swift does not import.
        return entries.compactMap { entry in
            guard let code = entry["kHISymbolicHotKeyCode"] as? NSNumber,
                let modifiers = entry["kHISymbolicHotKeyModifiers"] as? NSNumber
            else { return nil }
            return SystemShortcut(
                combination: Combination(keyCode: code.uint32Value, modifiers: modifiers.uint32Value & modifierMask),
                enabled: entry["kHISymbolicHotKeyEnabled"] as? Bool ?? false)
        }
    }

    /// Carbon modifiers from an event's modifier flags; only the four a hotkey carries.
    internal static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        return modifiers
    }

    /// Event modifier flags from Carbon modifiers, for a menu item's key equivalent.
    internal static func eventModifiers(_ modifiers: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    /// The modifiers as macOS shows them, in its order: ⌃ ⌥ ⇧ ⌘.
    internal static func symbols(_ modifiers: UInt32) -> String {
        [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
            .filter { modifiers & UInt32($0.0) != 0 }
            .map(\.1)
            .joined()
    }

    /// The combination as settings, the notices and the menu name it: `⌃⌘Space`.
    @MainActor
    internal static func displayName(_ combination: Combination) -> String {
        symbols(combination.modifiers) + keyName(combination.keyCode)
    }

    /// A key's name: from the table for keys that have one, else the character it types under the current
    /// keyboard layout, upper-cased as macOS shows it.
    @MainActor
    internal static func keyName(_ keyCode: UInt32) -> String {
        named[keyCode]?.name ?? typed(keyCode)?.uppercased() ?? "Key \(keyCode)"
    }

    /// The key as an `NSMenuItem` key equivalent; empty for a key that types nothing.
    @MainActor
    internal static func keyEquivalent(_ keyCode: UInt32) -> String {
        named[keyCode].map { String($0.equivalent) } ?? typed(keyCode) ?? ""
    }

    private static func function(_ key: Int) -> Character {
        // FORCE: the function-key constants are scalars in the private-use area, every one of them valid.
        // swift-format-ignore: NeverForceUnwrap
        // swiftlint:disable:next force_unwrapping
        Character(Unicode.Scalar(UInt32(key))!)
    }

    /// What the key types with no modifier under the current keyboard layout, or nil for nothing printable.
    ///
    /// Text Input Sources is read on the main thread only.
    @MainActor
    private static func typed(_ keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let layout = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var length = 0
        let capacity = 4
        var characters = [UniChar](repeating: 0, count: capacity)
        let status = layout.withUnsafeBytes { bytes in
            UCKeyTranslate(
                bytes.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self),
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysMask),
                &deadKeys,
                capacity,
                &length,
                &characters)
        }
        let text = String(utf16CodeUnits: characters, count: length)
        let printable = text.unicodeScalars.allSatisfy { $0.value > 0x20 && $0.value != 0x7F }
        guard status == noErr, !text.isEmpty, printable else { return nil }
        return text
    }
}
