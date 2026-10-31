import Carbon.HIToolbox
import Testing

@testable import Issoku

// The handler firing needs a real key press and is not tested; the run sheet records it.
@Suite("Hotkey")
@MainActor
internal struct HotkeyTests {
    @Test("The default registers once per process; after unregister it registers again")
    internal func registration() {
        let (keyCode, modifiers) = Hotkey.combination
        let first = Hotkey.register(keyCode: keyCode, modifiers: modifiers) {}
        #expect(first == noErr)
        #expect(Hotkey.statusText(for: first) == nil)

        let second = Hotkey.register(keyCode: keyCode, modifiers: modifiers) {}
        #expect(second == OSStatus(eventHotKeyExistsErr))
        let text = Hotkey.statusText(for: second)
        #expect(text?.contains("Control-Command-Space") == true)
        #expect(text?.contains("(\(eventHotKeyExistsErr))") == true)

        Hotkey.unregister()
        #expect(Hotkey.register(keyCode: keyCode, modifiers: modifiers) {} == noErr)
        Hotkey.unregister()
    }
}
