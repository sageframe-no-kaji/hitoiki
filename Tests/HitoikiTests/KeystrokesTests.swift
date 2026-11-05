import AppKit
import Carbon.HIToolbox
import Testing

@testable import Hitoiki

@Suite("Keystrokes")
internal struct KeystrokesTests {
    internal struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let characters: String?
        let modifiers: NSEvent.ModifierFlags
        let keyCode: Int
        let action: Keystrokes.Action
        var testDescription: String { name }

        init(
            _ name: String,
            _ characters: String?,
            _ modifiers: NSEvent.ModifierFlags,
            _ keyCode: Int,
            _ action: Keystrokes.Action
        ) {
            self.name = name
            self.characters = characters
            self.modifiers = modifiers
            self.keyCode = keyCode
            self.action = action
        }
    }

    // The characters are what AppKit puts in `NSEvent.characters` for the key: keypad Enter carries
    // ETX, Control-C carries ETX, an arrow carries a private-use function-key character.
    private static let cases: [Case] = [
        Case("a", "a", [], kVK_ANSI_A, .write([0x61])),
        Case("Shift-a", "A", .shift, kVK_ANSI_A, .write([0x41])),
        Case("Option é", "é", .option, kVK_ANSI_E, .write([0xC3, 0xA9])),
        Case("Return", "\r", [], kVK_Return, .write([0x0D])),
        Case("keypad Enter", "\u{03}", .numericPad, kVK_ANSI_KeypadEnter, .write([0x0D])),
        Case("Delete", "\u{7F}", [], kVK_Delete, .write([0x7F])),
        Case("Command-V", "v", .command, kVK_ANSI_V, .paste),
        Case("Control-C", "\u{03}", .control, kVK_ANSI_C, .stop),
        Case("Escape", "\u{1B}", [], kVK_Escape, .ignore),
        Case("Command-C", "c", .command, kVK_ANSI_C, .ignore),
        Case("Control-D", "\u{04}", .control, kVK_ANSI_D, .ignore),
        Case("Up arrow", "\u{F700}", [.numericPad, .function], kVK_UpArrow, .ignore),
        Case("no characters", nil, [], kVK_ANSI_A, .ignore),
    ]

    @Test("Each key maps to what Panel does with it while a command runs", arguments: cases)
    internal func maps(row: Case) {
        let keyCode = UInt16(row.keyCode)
        #expect(Keystrokes.action(characters: row.characters, modifiers: row.modifiers, keyCode: keyCode) == row.action)
    }
}
