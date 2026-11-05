import AppKit
import Carbon.HIToolbox

/// What a key pressed while a command runs becomes.
///
/// Nothing typed is drawn locally.
internal enum Keystrokes {
    /// What Panel does with one key.
    internal enum Action: Sendable, Equatable {
        /// Bytes for the pseudoterminal.
        case write([UInt8])
        /// Stop: interrupt first, kill after.
        case stop
        /// The general pasteboard's string, as bytes for the pseudoterminal.
        case paste
        /// Nothing reaches the command.
        case ignore
    }

    /// The action for a key, from the event's characters, modifier flags and virtual key code.
    ///
    /// Return and keypad Enter write a carriage return, Delete writes DEL, Command-V pastes,
    /// Control-C stops; printable characters, with or without Shift or Option, are written as
    /// UTF-8. Everything else, Escape and the cursor keys included, is ignored.
    internal static func action(characters: String?, modifiers: NSEvent.ModifierFlags, keyCode: UInt16) -> Action {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) {
            return characters == "v" ? .paste : .ignore
        }
        if flags.contains(.control) {
            return characters == "\u{03}" ? .stop : .ignore
        }
        switch Int(keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter:
            return .write([0x0D])
        case kVK_Delete:
            return .write([0x7F])
        default:
            break
        }
        guard let characters, !characters.isEmpty, characters.unicodeScalars.allSatisfy(printable) else {
            return .ignore
        }
        return .write(Array(characters.utf8))
    }

    /// Not a control character and not one of AppKit's function-key characters (U+F700–U+F8FF).
    private static func printable(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value >= 0x20 && scalar.value != 0x7F && !(0xF700...0xF8FF).contains(scalar.value)
    }
}
