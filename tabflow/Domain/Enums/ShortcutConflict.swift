import CoreGraphics
import Foundation

nonisolated enum ShortcutConflict: Equatable, Sendable {
    case none
    case tabFlow(String)
    case knownSystem(String)
    case registeredElsewhere
}

nonisolated enum KnownSystemShortcut: Equatable, Sendable, CaseIterable {
    case appSwitcher
    case spotlight
    case missionControl
    case appExpose
    case spaceLeft
    case spaceRight

    var shortcut: GlobalShortcut {
        switch self {
        case .appSwitcher:
            GlobalShortcut(keyCode: 48, modifiersRawValue: CGEventFlags.maskCommand.rawValue)
        case .spotlight:
            GlobalShortcut(keyCode: 49, modifiersRawValue: CGEventFlags.maskCommand.rawValue)
        case .missionControl:
            GlobalShortcut(keyCode: 126, modifiersRawValue: CGEventFlags.maskControl.rawValue)
        case .appExpose:
            GlobalShortcut(keyCode: 125, modifiersRawValue: CGEventFlags.maskControl.rawValue)
        case .spaceLeft:
            GlobalShortcut(keyCode: 123, modifiersRawValue: CGEventFlags.maskControl.rawValue)
        case .spaceRight:
            GlobalShortcut(keyCode: 124, modifiersRawValue: CGEventFlags.maskControl.rawValue)
        }
    }

    var reason: String {
        switch self {
        case .appSwitcher:
            String(localized: "settings.shortcuts.conflict.appSwitcher")
        case .spotlight:
            String(localized: "settings.shortcuts.conflict.spotlight")
        case .missionControl:
            String(localized: "settings.shortcuts.conflict.missionControl")
        case .appExpose:
            String(localized: "settings.shortcuts.conflict.appExpose")
        case .spaceLeft:
            String(localized: "settings.shortcuts.conflict.spaceLeft")
        case .spaceRight:
            String(localized: "settings.shortcuts.conflict.spaceRight")
        }
    }
}

nonisolated enum ShortcutConflictDetector {
    struct OwnedShortcut: Equatable, Sendable {
        let shortcut: GlobalShortcut
        let name: String
    }

    static func conflict(
        for shortcut: GlobalShortcut,
        existing: [OwnedShortcut] = [],
        registeredElsewhere: Bool = false
    ) -> ShortcutConflict {
        guard shortcut.isConfigured else { return .none }
        if let owned = existing.first(where: { $0.shortcut == shortcut }) {
            return .tabFlow(owned.name)
        }
        if let known = KnownSystemShortcut.allCases.first(where: { $0.shortcut == shortcut }) {
            return .knownSystem(known.reason)
        }
        if registeredElsewhere {
            return .registeredElsewhere
        }
        return .none
    }
}
