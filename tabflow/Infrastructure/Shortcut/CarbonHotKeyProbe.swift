import Carbon
import CoreGraphics
import Foundation

nonisolated protocol HotKeyRegistrationProbing: Sendable {
    func isRegisteredElsewhere(_ shortcut: GlobalShortcut) -> Bool
}

nonisolated struct CarbonHotKeyProbe: HotKeyRegistrationProbing {
    func isRegisteredElsewhere(_ shortcut: GlobalShortcut) -> Bool {
        guard shortcut.isConfigured else { return false }
        var hotKeyID = EventHotKeyID(signature: 0x5442464C, id: 1)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            Self.carbonModifiers(for: shortcut.eventFlags),
            hotKeyID,
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &hotKeyRef
        )
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        return status == eventHotKeyExistsErr
    }

    private static func carbonModifiers(for flags: CGEventFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.maskCommand) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.maskShift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.maskAlternate) { modifiers |= UInt32(optionKey) }
        if flags.contains(.maskControl) { modifiers |= UInt32(controlKey) }
        return modifiers
    }
}
