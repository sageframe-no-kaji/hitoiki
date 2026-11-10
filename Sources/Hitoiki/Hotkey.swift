import Carbon.HIToolbox

/// The global hotkey, registered with the Carbon event manager: no Accessibility permission and
/// no dependency.
///
/// At every instant one combination is registered: a replacement is registered while the old one is still
/// live, and the old one is released only once the new one has succeeded.
@MainActor
internal enum Hotkey {
    /// The combination registered now; nil only when the launch registration failed.
    internal private(set) static var registered: Shortcut.Combination?

    private static var handler: (@MainActor () -> Void)?
    private static var installed: EventHandlerRef?
    private static var reference: EventHotKeyRef?
    /// The id the next registration carries, so two registrations alive at once never share one.
    private static var nextID: UInt32 = 1

    /// The registered combination's name, as the notices and settings show it.
    internal static var displayName: String? {
        registered.map(Shortcut.displayName)
    }

    /// Registers `keyCode` with Carbon `modifiers` so a press calls `handler` on the main thread.
    ///
    /// - Returns: `noErr`, or the status from `InstallEventHandler` or `RegisterEventHotKey`;
    ///   `eventHotKeyExistsErr` when this process already holds the combination.
    internal static func register(
        keyCode: UInt32,
        modifiers: UInt32,
        handler: @escaping @MainActor () -> Void
    ) -> OSStatus {
        Self.handler = handler
        return replace(keyCode: keyCode, modifiers: modifiers)
    }

    /// Registers the new combination while the old one is still live, and releases the old one only if the
    /// new one succeeded; on failure nothing changes.
    ///
    /// - Returns: `noErr`, or the status that refused the new combination.
    internal static func replace(keyCode: UInt32, modifiers: UInt32) -> OSStatus {
        if installed == nil {
            var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), hotkeyPressed, 1, &pressed, nil, &installed)
            guard status == noErr else { return status }
        }
        var next: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: OSType(0x6973_736B), id: nextID)
        nextID &+= 1
        let status = RegisterEventHotKey(keyCode, modifiers, identifier, GetApplicationEventTarget(), 0, &next)
        guard status == noErr else { return status }
        if let reference { UnregisterEventHotKey(reference) }
        reference = next
        registered = Shortcut.Combination(keyCode: keyCode, modifiers: modifiers)
        return noErr
    }

    /// The recorder's candidate through the four checks: the first three refuse it with the reason, the
    /// fourth is its registration; only once it is registered is it stored.
    ///
    /// - Parameters:
    ///   - keyCode: The key pressed, or nil when modifiers were released with no key.
    ///   - modifiers: The Carbon modifiers held with it.
    ///   - settings: The store the combination is written to once registered.
    ///   - system: The system's shortcuts, read at the moment of recording.
    /// - Returns: Nil when the candidate is now the hotkey; otherwise the line saying why not.
    internal static func record(
        keyCode: UInt32?,
        modifiers: UInt32,
        into settings: Settings,
        system: [Shortcut.SystemShortcut]
    ) -> String? {
        switch Shortcut.verdict(keyCode: keyCode, modifiers: modifiers, system: system) {
        case .refused(let refusal):
            return refusal.message
        case .allowed(let candidate):
            let status = replace(keyCode: candidate.keyCode, modifiers: candidate.modifiers)
            guard status == noErr else { return statusText(for: status, combination: candidate) }
            settings.shortcut = candidate
            return nil
        }
    }

    /// Releases the registered combination, if any.
    internal static func unregister() {
        guard let reference else { return }
        UnregisterEventHotKey(reference)
        self.reference = nil
        registered = nil
    }

    /// Nil for `noErr`; otherwise the notice the panel and settings show for `combination`.
    internal static func statusText(for status: OSStatus, combination: Shortcut.Combination) -> String? {
        guard status != noErr else { return nil }
        return "\(Shortcut.displayName(combination)) is unavailable (\(status)). Another app or macOS may own it; "
            + "see System Settings > Keyboard > Keyboard Shortcuts."
    }

    /// The line settings shows: the registered combination, or, while none is, why the launch's failed.
    internal static func settingsLine(launch status: OSStatus, attempted: Shortcut.Combination) -> String {
        if let displayName { return "\(displayName) is registered." }
        return statusText(for: status, combination: attempted) ?? "No shortcut is registered."
    }

    /// Carbon calls this on the main thread, from the application event target.
    nonisolated private static let hotkeyPressed: EventHandlerUPP = { _, _, _ in
        MainActor.assumeIsolated { handler?() }
        return noErr
    }
}
