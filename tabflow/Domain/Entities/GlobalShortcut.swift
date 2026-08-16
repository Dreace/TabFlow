import AppKit
import CoreGraphics

struct GlobalShortcut: Codable, Equatable, Sendable {
    let keyCode: Int64
    let modifiersRawValue: UInt64

    static let defaultSwitcher = GlobalShortcut(
        keyCode: 48,
        modifiersRawValue: CGEventFlags.maskAlternate.rawValue
    )

    var eventFlags: CGEventFlags {
        CGEventFlags(rawValue: modifiersRawValue)
    }

    var displayName: String {
        var components: [String] = []
        let flags = eventFlags
        if flags.contains(.maskControl) { components.append("⌃") }
        if flags.contains(.maskAlternate) { components.append("⌥") }
        if flags.contains(.maskShift) { components.append("⇧") }
        if flags.contains(.maskCommand) { components.append("⌘") }
        components.append(keyName)
        return components.joined(separator: " ")
    }

    var hasKnownSystemConflict: Bool {
        let primaryModifiers = eventFlags.subtracting(.maskShift)
        guard primaryModifiers == .maskCommand else { return false }
        return keyCode == 48 || keyCode == 49
    }

    private var keyName: String {
        switch keyCode {
        case 48: "Tab"
        case 36: "Return"
        case 49: "Space"
        case 53: "Esc"
        case 123: "←"
        case 124: "→"
        case 125: "↓"
        case 126: "↑"
        default:
            String(
                format: String(localized: "shortcut.keyCode.format"),
                locale: .current,
                keyCode
            )
        }
    }

    static func from(event: NSEvent) -> GlobalShortcut? {
        // Shift is reserved for reverse traversal and is added by the shortcut engine.
        let allowed = event.modifierFlags.intersection([.command, .option, .control])
        guard !allowed.isEmpty else { return nil }
        var flags: CGEventFlags = []
        if allowed.contains(.command) { flags.insert(.maskCommand) }
        if allowed.contains(.option) { flags.insert(.maskAlternate) }
        if allowed.contains(.control) { flags.insert(.maskControl) }
        return GlobalShortcut(keyCode: Int64(event.keyCode), modifiersRawValue: flags.rawValue)
    }
}
