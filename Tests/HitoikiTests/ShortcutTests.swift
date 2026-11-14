import AppKit
import Carbon.HIToolbox
import Testing

@testable import Hitoiki

// Carbon's numbers, written out: the verdicts are checked against these, not against the code's own masks.
private let command: UInt32 = 256
private let shift: UInt32 = 512
private let capsLock: UInt32 = 1_024
private let option: UInt32 = 2_048
private let control: UInt32 = 4_096
private let space: UInt32 = 49
private let tab: UInt32 = 48
private let letterA: UInt32 = 0
private let digitOne: UInt32 = 18
private let functionFive: UInt32 = 96

private func combination(_ keyCode: UInt32, _ modifiers: UInt32) -> Shortcut.Combination {
    Shortcut.Combination(keyCode: keyCode, modifiers: modifiers)
}

private func shortcut(_ keyCode: UInt32, _ modifiers: UInt32, enabled: Bool) -> Shortcut.SystemShortcut {
    Shortcut.SystemShortcut(combination: combination(keyCode, modifiers), enabled: enabled)
}

@Suite("Shortcut")
internal struct ShortcutTests {
    internal struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let keyCode: UInt32?
        let modifiers: UInt32
        let system: [Shortcut.SystemShortcut]
        let verdict: Shortcut.Verdict
        var testDescription: String { name }

        init(
            _ name: String,
            _ keyCode: UInt32?,
            _ modifiers: UInt32,
            _ system: [Shortcut.SystemShortcut],
            _ verdict: Shortcut.Verdict
        ) {
            self.name = name
            self.keyCode = keyCode
            self.modifiers = modifiers
            self.system = system
            self.verdict = verdict
        }
    }

    // The recorder's refusals, checked in order, and the cases next to each that pass.
    private static let cases: [Case] = [
        Case("Command alone, released", nil, command, [], .refused(.noKey)),
        Case("no key and no modifier", nil, 0, [], .refused(.noKey)),
        Case("the Command key as the key", 55, command, [], .refused(.noKey)),
        Case("the Shift key as the key", 56, shift, [], .refused(.noKey)),
        Case("Shift-A", letterA, shift, [], .refused(.noQualifyingModifier)),
        Case("A alone", letterA, 0, [], .refused(.noQualifyingModifier)),
        Case("1 alone", digitOne, 0, [], .refused(.noQualifyingModifier)),
        Case("Caps Lock-A", letterA, capsLock, [], .refused(.noQualifyingModifier)),
        Case("F5 alone", functionFive, 0, [], .allowed(combination(functionFive, 0))),
        Case("Shift-F5", functionFive, shift, [], .allowed(combination(functionFive, shift))),
        Case("Option-A", letterA, option, [], .allowed(combination(letterA, option))),
        Case("Control-1", digitOne, control, [], .allowed(combination(digitOne, control))),
        Case(
            "Control-Command-Space, empty list",
            space,
            control | command,
            [],
            .allowed(combination(space, control | command))),
        Case(
            "Command-Space, enabled in the list",
            space,
            command,
            [shortcut(space, command, enabled: true)],
            .refused(.takenByMacOS)),
        Case(
            "Command-Space, disabled in the list",
            space,
            command,
            [shortcut(space, command, enabled: false)],
            .allowed(combination(space, command))),
        Case(
            "Command-Space with Caps Lock on, enabled in the list",
            space,
            command | capsLock,
            [shortcut(space, command, enabled: true)],
            .refused(.takenByMacOS)),
        Case(
            "Option-Command-Space, Command-Space enabled in the list",
            space,
            option | command,
            [shortcut(space, command, enabled: true)],
            .allowed(combination(space, option | command))),
        Case(
            "Shift-A, enabled in the list: check 2 comes first",
            letterA,
            shift,
            [shortcut(letterA, shift, enabled: true)],
            .refused(.noQualifyingModifier)),
        Case(
            "Command-Tab, empty list: nothing is refused by name", tab, command, [], .allowed(combination(tab, command))
        ),
    ]

    @Test("Each candidate gets the verdict of the four checks", arguments: cases)
    internal func verdicts(row: Case) {
        #expect(Shortcut.verdict(keyCode: row.keyCode, modifiers: row.modifiers, system: row.system) == row.verdict)
    }

    // The default is exempt from the system-list check on purpose (ho-05.1 Decision 14).
    @Test("The default, Control-Command-Space, passes check 3 against a list that holds it enabled")
    internal func defaultExempt() {
        let list = [
            shortcut(space, control | command, enabled: true),
            shortcut(space, command, enabled: true),
            shortcut(space, control | shift | command, enabled: true),
        ]
        #expect(
            Shortcut.verdict(keyCode: space, modifiers: control | command, system: list)
                == .allowed(combination(space, control | command)))
        // Caps Lock is not a modifier a hotkey carries: the candidate is still the default.
        #expect(
            Shortcut.verdict(keyCode: space, modifiers: control | command | capsLock, system: list)
                == .allowed(combination(space, control | command)))
        // A different enabled entry is refused, the default's neighbour with Shift among them.
        #expect(Shortcut.verdict(keyCode: space, modifiers: command, system: list) == .refused(.takenByMacOS))
        #expect(
            Shortcut.verdict(keyCode: space, modifiers: control | shift | command, system: list)
                == .refused(.takenByMacOS))
        // Checks 1 and 2 still come first: the default's modifiers released with no key are refused.
        #expect(Shortcut.verdict(keyCode: nil, modifiers: control | command, system: list) == .refused(.noKey))
    }

    @Test("The refusals' lines")
    internal func messages() {
        #expect(Shortcut.Refusal.noKey.message == "Press a key with Command, Control or Option.")
        #expect(Shortcut.Refusal.noQualifyingModifier.message == "Press a key with Command, Control or Option.")
        #expect(Shortcut.Refusal.takenByMacOS.message == "Taken by macOS.")
    }

    @Test("Discovery: the system's list is read, and it reports the app switcher, so Command-Tab is refused from it")
    internal func systemList() {
        let list = Shortcut.systemShortcuts()
        #expect(!list.isEmpty)
        #expect(list.allSatisfy { $0.combination.modifiers & ~(control | option | shift | command) == 0 })
        #expect(list.contains(shortcut(tab, command, enabled: true)))
        #expect(list.contains(shortcut(tab, shift | command, enabled: true)))
        #expect(Shortcut.verdict(keyCode: tab, modifiers: command, system: list) == .refused(.takenByMacOS))
        // The default passes check 3 against the system's own list, whatever it says.
        #expect(
            Shortcut.verdict(keyCode: space, modifiers: control | command, system: list)
                == .allowed(combination(space, control | command)))
        // Every other enabled entry the system reports is refused against the system's own list.
        for entry in list where entry.enabled && entry.combination != combination(space, control | command) {
            let verdict = Shortcut.verdict(
                keyCode: entry.combination.keyCode, modifiers: entry.combination.modifiers, system: list)
            #expect(verdict != .allowed(entry.combination))
        }
    }

    @Test("Event flags become Carbon modifiers and back; Caps Lock and the function key are dropped")
    internal func translation() {
        let flags: NSEvent.ModifierFlags = [.command, .shift, .capsLock, .function, .numericPad]
        #expect(Shortcut.carbonModifiers(flags) == command | shift)
        #expect(Shortcut.carbonModifiers([.control, .option]) == control | option)
        #expect(Shortcut.carbonModifiers([]) == 0)
        #expect(Shortcut.eventModifiers(control | option | shift | command) == [.control, .option, .shift, .command])
        #expect(Shortcut.eventModifiers(capsLock).isEmpty)
    }
}

// Display names read the keyboard layout, which is read on the main thread.
@Suite("Shortcut names")
@MainActor
internal struct ShortcutNameTests {
    @Test("Modifier symbols in macOS's order, then the key's name")
    internal func names() {
        #expect(Shortcut.displayName(combination(space, control | command)) == "⌃⌘Space")
        #expect(Shortcut.displayName(combination(functionFive, option | shift)) == "⌥⇧F5")
        #expect(Shortcut.displayName(combination(letterA, command | shift | option | control)) == "⌃⌥⇧⌘A")
        #expect(Shortcut.displayName(combination(36, control)) == "⌃Return")
        #expect(Shortcut.displayName(combination(117, option)) == "⌥Forward Delete")
        #expect(Shortcut.displayName(combination(123, control)) == "⌃Left Arrow")
        #expect(Shortcut.displayName(combination(80, 0)) == "F19")
        #expect(Shortcut.displayName(combination(122, 0)) == "F1")
    }

    // The guest's layout is ABC (US): kVK_ANSI_A types `a` and kVK_ANSI_1 types `1`.
    @Test("An ordinary key is named by what it types under the current layout, upper-cased")
    internal func layout() {
        #expect(Shortcut.displayName(combination(letterA, command)) == "⌘A")
        #expect(Shortcut.displayName(combination(digitOne, control)) == "⌃1")
        #expect(Shortcut.keyName(43) == ",")
    }

    @Test("A key that types nothing printable and has no name is named by its code")
    internal func unnamed() {
        // kVK_Help: the layout gives it a control character.
        #expect(Shortcut.keyName(114) == "Key 114")
        #expect(Shortcut.keyEquivalent(114).isEmpty)
    }

    @Test("Key equivalents for a menu: the typed character, or the named key's own")
    internal func keyEquivalents() {
        #expect(Shortcut.keyEquivalent(letterA) == "a")
        #expect(Shortcut.keyEquivalent(space) == " ")
        #expect(Shortcut.keyEquivalent(36) == "\r")
        // NSF5FunctionKey and NSLeftArrowFunctionKey.
        #expect(Shortcut.keyEquivalent(functionFive) == "\u{F708}")
        #expect(Shortcut.keyEquivalent(123) == "\u{F702}")
    }
}
