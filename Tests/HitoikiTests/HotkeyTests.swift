import Carbon.HIToolbox
import Testing

@testable import Hitoiki

/// Combinations no system or app shortcut takes: all four modifiers with J, K and L.
private let held = Shortcut.Combination(
    keyCode: UInt32(kVK_ANSI_J), modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey))
private let spare = Shortcut.Combination(
    keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey))
private let other = Shortcut.Combination(
    keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey))

/// Registers `combination` from the test, apart from `Hotkey`: `eventHotKeyExistsErr` means this process
/// already holds it, `noErr` that it did not (the test then holds it, and releases it with the reference).
@MainActor
private func probe(_ combination: Shortcut.Combination) -> (status: OSStatus, reference: EventHotKeyRef?) {
    var reference: EventHotKeyRef?
    let status = RegisterEventHotKey(
        combination.keyCode,
        combination.modifiers,
        EventHotKeyID(signature: OSType(0x7465_7374), id: 99),
        GetApplicationEventTarget(),
        0,
        &reference)
    return (status, reference)
}

/// True when this process holds `combination`; the probe's own registration, if any, is released.
@MainActor
private func isHeld(_ combination: Shortcut.Combination) -> Bool {
    let (status, reference) = probe(combination)
    if let reference { UnregisterEventHotKey(reference) }
    return status == OSStatus(eventHotKeyExistsErr)
}

// Real Carbon registrations in the test process. Every test is synchronous on the main actor, so no other
// suite's test runs between its registrations, and each leaves nothing registered.
// The handler firing needs a real key press and is not tested; the run sheet records it.
@Suite("Hotkey", .serialized)
@MainActor
internal struct HotkeyTests {
    @Test("The default registers once per process; after unregister it registers again")
    internal func registration() {
        let shortcut = Settings.defaultShortcut
        let first = Hotkey.register(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) {}
        #expect(first == noErr)
        #expect(Hotkey.statusText(for: first, combination: shortcut) == nil)
        #expect(Hotkey.registered == shortcut)

        let second = Hotkey.replace(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers)
        #expect(second == OSStatus(eventHotKeyExistsErr))
        let text = Hotkey.statusText(for: second, combination: shortcut)
        #expect(text?.hasPrefix("⌃⌘Space is unavailable (\(eventHotKeyExistsErr)).") == true)

        Hotkey.unregister()
        #expect(Hotkey.registered == nil)
        #expect(!isHeld(shortcut))
        #expect(Hotkey.register(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) {} == noErr)
        Hotkey.unregister()
    }

    @Test("Replace to a free combination: the new one is held, the old one released; replace back works")
    internal func replaceFree() {
        #expect(Hotkey.register(keyCode: held.keyCode, modifiers: held.modifiers) {} == noErr)
        defer { Hotkey.unregister() }
        #expect(Hotkey.replace(keyCode: spare.keyCode, modifiers: spare.modifiers) == noErr)
        #expect(Hotkey.registered == spare)
        #expect(isHeld(spare))
        #expect(!isHeld(held))

        #expect(Hotkey.replace(keyCode: held.keyCode, modifiers: held.modifiers) == noErr)
        #expect(Hotkey.registered == held)
        #expect(isHeld(held))
        #expect(!isHeld(spare))
    }

    @Test("Replace to a combination the process already holds: refused, and the old one stays registered")
    internal func replaceHeld() throws {
        let (status, reference) = probe(other)
        try #require(status == noErr)
        defer { if let reference { UnregisterEventHotKey(reference) } }
        #expect(Hotkey.register(keyCode: held.keyCode, modifiers: held.modifiers) {} == noErr)
        defer { Hotkey.unregister() }

        #expect(Hotkey.replace(keyCode: other.keyCode, modifiers: other.modifiers) == OSStatus(eventHotKeyExistsErr))
        #expect(Hotkey.registered == held)
        #expect(isHeld(held))
    }

    @Test("Recording: a refused candidate changes neither the hotkey nor the store; an accepted one is both")
    internal func record() throws {
        let suite = try ThrowawaySuite()
        defer { suite.remove() }
        let settings = Settings(defaults: suite.defaults)
        #expect(Hotkey.register(keyCode: held.keyCode, modifiers: held.modifiers) {} == noErr)
        defer { Hotkey.unregister() }
        let taken = [Shortcut.SystemShortcut(combination: spare, enabled: true)]

        // Checks 1 to 3: the line, and nothing changed.
        let refusals: [(candidate: Shortcut.Combination?, line: String)] = [
            (nil, "Press a key with Command, Control or Option."),
            (
                Shortcut.Combination(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(shiftKey)),
                "Press a key with Command, Control or Option."
            ),
            (spare, "Taken by macOS."),
        ]
        for (candidate, line) in refusals {
            let modifiers = candidate?.modifiers ?? UInt32(cmdKey)
            #expect(
                Hotkey.record(keyCode: candidate?.keyCode, modifiers: modifiers, into: settings, system: taken) == line)
            #expect(Hotkey.registered == held)
            #expect(isHeld(held))
            #expect(suite.keys.isEmpty)
        }

        // Check 4: the system refuses the registration.
        let (status, reference) = probe(other)
        try #require(status == noErr)
        let line = Hotkey.record(keyCode: other.keyCode, modifiers: other.modifiers, into: settings, system: [])
        if let reference { UnregisterEventHotKey(reference) }
        #expect(line?.hasPrefix("⌃⌥⇧⌘L is unavailable (\(eventHotKeyExistsErr)).") == true)
        #expect(Hotkey.registered == held)
        #expect(isHeld(held))
        #expect(suite.keys.isEmpty)

        // Accepted: registered, the old one released, then stored.
        #expect(Hotkey.record(keyCode: other.keyCode, modifiers: other.modifiers, into: settings, system: []) == nil)
        #expect(Hotkey.registered == other)
        #expect(isHeld(other))
        #expect(!isHeld(held))
        #expect(Settings(defaults: suite.defaults).shortcut == other)
    }
}
