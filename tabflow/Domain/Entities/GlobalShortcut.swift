import AppKit
import Carbon.HIToolbox
import CoreGraphics

struct GlobalShortcut: Codable, Equatable, Sendable {
    let keyCode: Int64
    let modifiersRawValue: UInt64

    static let defaultSwitcher = GlobalShortcut(
        keyCode: 48,
        modifiersRawValue: CGEventFlags.maskAlternate.rawValue
    )

    static let none = GlobalShortcut(keyCode: 0, modifiersRawValue: 0)

    var eventFlags: CGEventFlags {
        CGEventFlags(rawValue: modifiersRawValue)
    }

    var isConfigured: Bool {
        !eventFlags.intersection([.maskCommand, .maskAlternate, .maskControl]).isEmpty
    }

    var displayName: String {
        guard isConfigured else {
            return String(localized: "shortcut.none")
        }
        var components: [String] = []
        let flags = eventFlags
        if flags.contains(.maskControl) { components.append("⌃") }
        if flags.contains(.maskAlternate) { components.append("⌥") }
        if flags.contains(.maskShift) { components.append("⇧") }
        if flags.contains(.maskCommand) { components.append("⌘") }
        components.append(ShortcutKeyName.displayName(for: keyCode))
        return components.joined(separator: " ")
    }

    static func from(event: NSEvent) -> GlobalShortcut? {
        from(modifierFlags: event.modifierFlags, keyCode: event.keyCode)
    }

    static func from(eventFlags: CGEventFlags, keyCode: Int64) -> GlobalShortcut? {
        guard keyCode >= 0, keyCode <= Int64(UInt16.max) else { return nil }
        var modifierFlags: NSEvent.ModifierFlags = []
        if eventFlags.contains(.maskCommand) { modifierFlags.insert(.command) }
        if eventFlags.contains(.maskAlternate) { modifierFlags.insert(.option) }
        if eventFlags.contains(.maskControl) { modifierFlags.insert(.control) }
        return from(modifierFlags: modifierFlags, keyCode: UInt16(keyCode))
    }

    static func from(modifierFlags: NSEvent.ModifierFlags, keyCode: UInt16) -> GlobalShortcut? {
        // Shift is reserved for reverse traversal and is added by the shortcut engine.
        let allowed = modifierFlags.intersection([.command, .option, .control])
        guard !allowed.isEmpty else { return nil }
        var flags: CGEventFlags = []
        if allowed.contains(.command) { flags.insert(.maskCommand) }
        if allowed.contains(.option) { flags.insert(.maskAlternate) }
        if allowed.contains(.control) { flags.insert(.maskControl) }
        return GlobalShortcut(keyCode: Int64(keyCode), modifiersRawValue: flags.rawValue)
    }
}

nonisolated enum ShortcutKeyName {
    static func displayName(for keyCode: Int64) -> String {
        if let name = names[keyCode] {
            return name
        }
        return String(
            format: String(localized: "shortcut.keyCode.format"),
            locale: .current,
            keyCode
        )
    }

    private static let names: [Int64: String] = [
        Int64(kVK_ANSI_A): "A",
        Int64(kVK_ANSI_B): "B",
        Int64(kVK_ANSI_C): "C",
        Int64(kVK_ANSI_D): "D",
        Int64(kVK_ANSI_E): "E",
        Int64(kVK_ANSI_F): "F",
        Int64(kVK_ANSI_G): "G",
        Int64(kVK_ANSI_H): "H",
        Int64(kVK_ANSI_I): "I",
        Int64(kVK_ANSI_J): "J",
        Int64(kVK_ANSI_K): "K",
        Int64(kVK_ANSI_L): "L",
        Int64(kVK_ANSI_M): "M",
        Int64(kVK_ANSI_N): "N",
        Int64(kVK_ANSI_O): "O",
        Int64(kVK_ANSI_P): "P",
        Int64(kVK_ANSI_Q): "Q",
        Int64(kVK_ANSI_R): "R",
        Int64(kVK_ANSI_S): "S",
        Int64(kVK_ANSI_T): "T",
        Int64(kVK_ANSI_U): "U",
        Int64(kVK_ANSI_V): "V",
        Int64(kVK_ANSI_W): "W",
        Int64(kVK_ANSI_X): "X",
        Int64(kVK_ANSI_Y): "Y",
        Int64(kVK_ANSI_Z): "Z",
        Int64(kVK_ANSI_0): "0",
        Int64(kVK_ANSI_1): "1",
        Int64(kVK_ANSI_2): "2",
        Int64(kVK_ANSI_3): "3",
        Int64(kVK_ANSI_4): "4",
        Int64(kVK_ANSI_5): "5",
        Int64(kVK_ANSI_6): "6",
        Int64(kVK_ANSI_7): "7",
        Int64(kVK_ANSI_8): "8",
        Int64(kVK_ANSI_9): "9",
        Int64(kVK_ANSI_Equal): "=",
        Int64(kVK_ANSI_Minus): "-",
        Int64(kVK_ANSI_RightBracket): "]",
        Int64(kVK_ANSI_LeftBracket): "[",
        Int64(kVK_ANSI_Quote): "'",
        Int64(kVK_ANSI_Semicolon): ";",
        Int64(kVK_ANSI_Backslash): "\\",
        Int64(kVK_ANSI_Comma): ",",
        Int64(kVK_ANSI_Slash): "/",
        Int64(kVK_ANSI_Period): ".",
        Int64(kVK_ANSI_Grave): "`",
        Int64(kVK_ANSI_KeypadDecimal): ".",
        Int64(kVK_ANSI_KeypadMultiply): "*",
        Int64(kVK_ANSI_KeypadPlus): "+",
        Int64(kVK_ANSI_KeypadDivide): "/",
        Int64(kVK_ANSI_KeypadMinus): "-",
        Int64(kVK_ANSI_KeypadEquals): "=",
        Int64(kVK_ANSI_Keypad0): "0",
        Int64(kVK_ANSI_Keypad1): "1",
        Int64(kVK_ANSI_Keypad2): "2",
        Int64(kVK_ANSI_Keypad3): "3",
        Int64(kVK_ANSI_Keypad4): "4",
        Int64(kVK_ANSI_Keypad5): "5",
        Int64(kVK_ANSI_Keypad6): "6",
        Int64(kVK_ANSI_Keypad7): "7",
        Int64(kVK_ANSI_Keypad8): "8",
        Int64(kVK_ANSI_Keypad9): "9",
        Int64(kVK_ANSI_KeypadClear): "Clear",
        Int64(kVK_ANSI_KeypadEnter): "Enter",
        Int64(kVK_Return): "Return",
        Int64(kVK_Tab): "Tab",
        Int64(kVK_Space): "Space",
        Int64(kVK_Delete): "Delete",
        Int64(kVK_Escape): "Esc",
        Int64(kVK_ForwardDelete): "Forward Delete",
        Int64(kVK_Home): "Home",
        Int64(kVK_End): "End",
        Int64(kVK_PageUp): "Page Up",
        Int64(kVK_PageDown): "Page Down",
        Int64(kVK_Help): "Help",
        Int64(kVK_F1): "F1",
        Int64(kVK_F2): "F2",
        Int64(kVK_F3): "F3",
        Int64(kVK_F4): "F4",
        Int64(kVK_F5): "F5",
        Int64(kVK_F6): "F6",
        Int64(kVK_F7): "F7",
        Int64(kVK_F8): "F8",
        Int64(kVK_F9): "F9",
        Int64(kVK_F10): "F10",
        Int64(kVK_F11): "F11",
        Int64(kVK_F12): "F12",
        Int64(kVK_F13): "F13",
        Int64(kVK_F14): "F14",
        Int64(kVK_F15): "F15",
        Int64(kVK_F16): "F16",
        Int64(kVK_F17): "F17",
        Int64(kVK_F18): "F18",
        Int64(kVK_F19): "F19",
        Int64(kVK_F20): "F20",
        Int64(kVK_LeftArrow): "←",
        Int64(kVK_RightArrow): "→",
        Int64(kVK_DownArrow): "↓",
        Int64(kVK_UpArrow): "↑"
    ]
}
