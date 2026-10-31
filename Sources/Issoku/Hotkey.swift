import Carbon.HIToolbox

/// The global hotkey, registered with the Carbon event manager: no Accessibility permission and
/// no dependency.
@MainActor
internal enum Hotkey {
    /// Control-Command-Space; the shortcut recorder is ho-05's.
    internal static let combination = (keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | cmdKey))

    private static var handler: (@MainActor () -> Void)?
    private static var installed: EventHandlerRef?
    private static var registered: EventHotKeyRef?

    /// Registers `keyCode` with Carbon `modifiers` so a press calls `handler` on the main thread.
    ///
    /// - Returns: `noErr`, or the status from `InstallEventHandler` or `RegisterEventHotKey`;
    ///   `eventHotKeyExistsErr` when this process already holds the combination.
    internal static func register(
        keyCode: UInt32,
        modifiers: UInt32,
        handler: @escaping @MainActor () -> Void
    ) -> OSStatus {
        if installed == nil {
            var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), hotkeyPressed, 1, &pressed, nil, &installed)
            guard status == noErr else { return status }
        }
        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: OSType(0x6973_736B), id: 1)
        let status = RegisterEventHotKey(keyCode, modifiers, identifier, GetApplicationEventTarget(), 0, &reference)
        if status == noErr {
            registered = reference
            Self.handler = handler
        }
        return status
    }

    /// Releases the registered combination, if any.
    internal static func unregister() {
        guard let registered else { return }
        UnregisterEventHotKey(registered)
        self.registered = nil
    }

    /// Nil for `noErr`; otherwise the notice the panel and Settings show.
    nonisolated internal static func statusText(for status: OSStatus) -> String? {
        guard status != noErr else { return nil }
        return "Control-Command-Space is unavailable (\(status)). Another app or macOS may own it; "
            + "see System Settings > Keyboard > Keyboard Shortcuts."
    }

    /// Carbon calls this on the main thread, from the application event target.
    nonisolated private static let hotkeyPressed: EventHandlerUPP = { _, _, _ in
        MainActor.assumeIsolated { handler?() }
        return noErr
    }
}
