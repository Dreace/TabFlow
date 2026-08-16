import Foundation
import Observation

nonisolated enum OverlayLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case horizontal
    case grid
    case list

    var id: Self { self }
}

nonisolated enum CardSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case small
    case medium
    case large

    var id: Self { self }
}

nonisolated struct OverlayLayoutAppearance: Codable, Equatable, Sendable {
    var cardSize: CardSize
    var showsThumbnails: Bool
    var showsApplicationName: Bool
    var showsWindowTitle: Bool
    var showsWindowStatus: Bool

    static let `default` = OverlayLayoutAppearance(
        cardSize: .medium,
        showsThumbnails: true,
        showsApplicationName: true,
        showsWindowTitle: true,
        showsWindowStatus: true
    )

    static func defaultsByLayout() -> [OverlayLayout: OverlayLayoutAppearance] {
        Dictionary(uniqueKeysWithValues: OverlayLayout.allCases.map { ($0, .default) })
    }
}

nonisolated enum OverlayLayoutAppearanceSupport {
    static func supportsCardSize(_ layout: OverlayLayout) -> Bool {
        layout != .list
    }

    static func supportsThumbnails(_ layout: OverlayLayout) -> Bool {
        layout != .list
    }
}

nonisolated enum OverlayPosition: String, CaseIterable, Identifiable, Sendable {
    case activeWindowDisplay
    case mouseDisplay
    case mainDisplay
    case fixedDisplay

    var id: Self { self }
}

nonisolated enum AnimationPreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case reduced
    case none

    var id: Self { self }
}

nonisolated enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: Self { self }
}

nonisolated enum WindowSortOrder: String, CaseIterable, Identifiable, Sendable {
    case recent
    case application
    case title
    case display

    var id: Self { self }
}

nonisolated enum PointerMovement: String, CaseIterable, Identifiable, Sendable {
    case none
    case windowCenter
    case displayCenter

    var id: Self { self }
}

nonisolated enum WindowRefreshInterval: String, CaseIterable, Identifiable, Sendable {
    case oneSecond
    case threeSeconds
    case fiveSeconds
    case tenSeconds
    case thirtySeconds

    var id: Self { self }

    var normalized: WindowRefreshInterval {
        switch self {
        case .oneSecond, .threeSeconds:
            .fiveSeconds
        case .fiveSeconds, .tenSeconds, .thirtySeconds:
            self
        }
    }

    var duration: Duration {
        switch normalized {
        case .oneSecond: .seconds(1)
        case .threeSeconds: .seconds(3)
        case .fiveSeconds: .seconds(5)
        case .tenSeconds: .seconds(10)
        case .thirtySeconds: .seconds(30)
        }
    }
}

@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let paused = "paused"
        static let showsMenuBarIcon = "showsMenuBarIcon"
        static let checkPermissions = "checkPermissions"
        static let confirmOnRelease = "confirmOnRelease"
        static let shortcut = "shortcut"
        static let confirmWithReturn = "confirmWithReturn"
        static let arrowNavigation = "arrowNavigation"
        static let layout = "layout"
        static let layoutAppearances = "layoutAppearances"
        static let cardSize = "cardSize"
        static let showsThumbnails = "showsThumbnails"
        static let showsApplicationName = "showsApplicationName"
        static let showsWindowTitle = "showsWindowTitle"
        static let showsStatus = "showsStatus"
        static let showsSearchField = "showsSearchField"
        static let showsKeyboardHint = "showsKeyboardHint"
        static let overlayPosition = "overlayPosition"
        static let fixedDisplayIdentifier = "fixedDisplayIdentifier"
        static let animation = "animation"
        static let appearance = "appearance"
        static let currentSpaceOnly = "currentSpaceOnly"
        static let currentDisplayOnly = "currentDisplayOnly"
        static let includesMinimized = "includesMinimized"
        static let includesHidden = "includesHidden"
        static let includesDialogs = "includesDialogs"
        static let includesUntitled = "includesUntitled"
        static let ignoredBundleIdentifiers = "ignoredBundleIdentifiers"
        static let sortOrder = "sortOrder"
        static let includesCurrentWindow = "includesCurrentWindow"
        static let selectsPreviousWindow = "selectsPreviousWindow"
        static let groupsApplications = "groupsApplications"
        static let restoresMinimized = "restoresMinimized"
        static let pointerMovement = "pointerMovement"
        static let windowRefreshInterval = "windowRefreshInterval"
        static let diagnosticsEnabled = "diagnosticsEnabled"
        static let requestedInputMonitoringPermission = "requestedInputMonitoringPermission"
        static let requestedScreenRecordingPermission = "requestedScreenRecordingPermission"
        static let onboardingCompleted = "onboardingCompleted"
    }

    private let store: SettingsStoring

    var isPaused: Bool { didSet { save(isPaused, for: Key.paused); onShortcutConfigurationChange?() } }
    var showsMenuBarIcon: Bool { didSet { save(showsMenuBarIcon, for: Key.showsMenuBarIcon); onShortcutConfigurationChange?() } }
    var checksPermissionsAtLaunch: Bool { didSet { save(checksPermissionsAtLaunch, for: Key.checkPermissions) } }
    var confirmsOnModifierRelease: Bool { didSet { save(confirmsOnModifierRelease, for: Key.confirmOnRelease); onShortcutConfigurationChange?() } }
    var shortcut: GlobalShortcut {
        didSet {
            if let data = try? JSONEncoder().encode(shortcut) {
                save(data, for: Key.shortcut)
            }
            onShortcutConfigurationChange?()
        }
    }
    var confirmsWithReturn: Bool { didSet { save(confirmsWithReturn, for: Key.confirmWithReturn); onShortcutConfigurationChange?() } }
    var supportsArrowNavigation: Bool { didSet { save(supportsArrowNavigation, for: Key.arrowNavigation); onShortcutConfigurationChange?() } }
    var overlayLayout: OverlayLayout {
        didSet {
            save(overlayLayout.rawValue, for: Key.layout)
            mirrorLegacyAppearanceKeys()
            onThumbnailVisibilityChange?(shouldCaptureThumbnails)
        }
    }
    var cardSize: CardSize {
        get { currentLayoutAppearance.cardSize }
        set { updateCurrentLayoutAppearance { $0.cardSize = newValue } }
    }
    var showsThumbnails: Bool {
        get { currentLayoutAppearance.showsThumbnails }
        set {
            updateCurrentLayoutAppearance { $0.showsThumbnails = newValue }
            onThumbnailVisibilityChange?(shouldCaptureThumbnails)
        }
    }
    var showsApplicationName: Bool {
        get { currentLayoutAppearance.showsApplicationName }
        set { updateCurrentLayoutAppearance { $0.showsApplicationName = newValue } }
    }
    var showsWindowTitle: Bool {
        get { currentLayoutAppearance.showsWindowTitle }
        set { updateCurrentLayoutAppearance { $0.showsWindowTitle = newValue } }
    }
    var showsWindowStatus: Bool {
        get { currentLayoutAppearance.showsWindowStatus }
        set { updateCurrentLayoutAppearance { $0.showsWindowStatus = newValue } }
    }
    var shouldCaptureThumbnails: Bool {
        OverlayLayoutAppearanceSupport.supportsThumbnails(overlayLayout) && showsThumbnails
    }
    var showsThumbnailsInAnySupportedLayout: Bool {
        OverlayLayout.allCases.contains { layout in
            OverlayLayoutAppearanceSupport.supportsThumbnails(layout)
                && (layoutAppearances[layout]?.showsThumbnails ?? true)
        }
    }
    var showsSearchField: Bool { didSet { save(showsSearchField, for: Key.showsSearchField); onShortcutConfigurationChange?() } }
    var showsKeyboardHint: Bool { didSet { save(showsKeyboardHint, for: Key.showsKeyboardHint) } }
    var overlayPosition: OverlayPosition { didSet { save(overlayPosition.rawValue, for: Key.overlayPosition) } }
    var fixedDisplayIdentifier: String { didSet { save(fixedDisplayIdentifier, for: Key.fixedDisplayIdentifier) } }
    var animationPreference: AnimationPreference { didSet { save(animationPreference.rawValue, for: Key.animation) } }
    var appearance: AppAppearance {
        didSet {
            save(appearance.rawValue, for: Key.appearance)
            onAppearanceChange?()
        }
    }
    var currentSpaceOnly: Bool { didSet { save(currentSpaceOnly, for: Key.currentSpaceOnly) } }
    var currentDisplayOnly: Bool { didSet { save(currentDisplayOnly, for: Key.currentDisplayOnly) } }
    var includesMinimizedWindows: Bool { didSet { save(includesMinimizedWindows, for: Key.includesMinimized) } }
    var includesHiddenApplications: Bool { didSet { save(includesHiddenApplications, for: Key.includesHidden) } }
    var includesDialogs: Bool { didSet { save(includesDialogs, for: Key.includesDialogs) } }
    var includesUntitledWindows: Bool { didSet { save(includesUntitledWindows, for: Key.includesUntitled) } }
    var ignoredBundleIdentifiers: Set<String> { didSet { save(Array(ignoredBundleIdentifiers).sorted(), for: Key.ignoredBundleIdentifiers) } }
    var sortOrder: WindowSortOrder { didSet { save(sortOrder.rawValue, for: Key.sortOrder) } }
    var includesCurrentWindow: Bool { didSet { save(includesCurrentWindow, for: Key.includesCurrentWindow) } }
    var selectsPreviousWindow: Bool { didSet { save(selectsPreviousWindow, for: Key.selectsPreviousWindow) } }
    var groupsApplications: Bool { didSet { save(groupsApplications, for: Key.groupsApplications) } }
    var restoresMinimizedWindows: Bool { didSet { save(restoresMinimizedWindows, for: Key.restoresMinimized) } }
    var pointerMovement: PointerMovement { didSet { save(pointerMovement.rawValue, for: Key.pointerMovement) } }
    var windowRefreshInterval: WindowRefreshInterval {
        didSet {
            save(windowRefreshInterval.rawValue, for: Key.windowRefreshInterval)
            onWindowRefreshIntervalChange?()
        }
    }
    var diagnosticsEnabled: Bool {
        didSet {
            save(diagnosticsEnabled, for: Key.diagnosticsEnabled)
            WindowDiagnosticLogging.isEnabled = diagnosticsEnabled
        }
    }
    var hasRequestedInputMonitoringPermission: Bool { didSet { save(hasRequestedInputMonitoringPermission, for: Key.requestedInputMonitoringPermission) } }
    var hasRequestedScreenRecordingPermission: Bool { didSet { save(hasRequestedScreenRecordingPermission, for: Key.requestedScreenRecordingPermission) } }
    var onboardingCompleted: Bool { didSet { save(onboardingCompleted, for: Key.onboardingCompleted) } }
    var onShortcutConfigurationChange: (() -> Void)?
    var onThumbnailVisibilityChange: ((Bool) -> Void)?
    var onWindowRefreshIntervalChange: (() -> Void)?
    var onAppearanceChange: (() -> Void)?
    private var layoutAppearances: [OverlayLayout: OverlayLayoutAppearance]

    init(store: SettingsStoring) {
        self.store = store
        isPaused = store.bool(forKey: Key.paused) ?? false
        showsMenuBarIcon = store.bool(forKey: Key.showsMenuBarIcon) ?? true
        checksPermissionsAtLaunch = store.bool(forKey: Key.checkPermissions) ?? true
        confirmsOnModifierRelease = store.bool(forKey: Key.confirmOnRelease) ?? true
        shortcut = store.data(forKey: Key.shortcut)
            .flatMap { try? JSONDecoder().decode(GlobalShortcut.self, from: $0) }
            ?? .defaultSwitcher
        confirmsWithReturn = store.bool(forKey: Key.confirmWithReturn) ?? true
        supportsArrowNavigation = store.bool(forKey: Key.arrowNavigation) ?? true
        overlayLayout = OverlayLayout(rawValue: store.string(forKey: Key.layout) ?? "") ?? .automatic
        layoutAppearances = Self.loadLayoutAppearances(from: store)
        showsSearchField = store.bool(forKey: Key.showsSearchField) ?? false
        showsKeyboardHint = store.bool(forKey: Key.showsKeyboardHint) ?? true
        overlayPosition = OverlayPosition(rawValue: store.string(forKey: Key.overlayPosition) ?? "") ?? .activeWindowDisplay
        fixedDisplayIdentifier = store.string(forKey: Key.fixedDisplayIdentifier) ?? ""
        animationPreference = AnimationPreference(rawValue: store.string(forKey: Key.animation) ?? "") ?? .system
        appearance = AppAppearance(rawValue: store.string(forKey: Key.appearance) ?? "") ?? .system
        currentSpaceOnly = store.bool(forKey: Key.currentSpaceOnly) ?? false
        currentDisplayOnly = store.bool(forKey: Key.currentDisplayOnly) ?? false
        includesMinimizedWindows = store.bool(forKey: Key.includesMinimized) ?? true
        includesHiddenApplications = store.bool(forKey: Key.includesHidden) ?? true
        includesDialogs = store.bool(forKey: Key.includesDialogs) ?? true
        includesUntitledWindows = store.bool(forKey: Key.includesUntitled) ?? true
        ignoredBundleIdentifiers = Set(store.strings(forKey: Key.ignoredBundleIdentifiers) ?? [])
        sortOrder = WindowSortOrder(rawValue: store.string(forKey: Key.sortOrder) ?? "") ?? .recent
        includesCurrentWindow = store.bool(forKey: Key.includesCurrentWindow) ?? true
        selectsPreviousWindow = store.bool(forKey: Key.selectsPreviousWindow) ?? true
        groupsApplications = store.bool(forKey: Key.groupsApplications) ?? false
        restoresMinimizedWindows = store.bool(forKey: Key.restoresMinimized) ?? true
        pointerMovement = PointerMovement(rawValue: store.string(forKey: Key.pointerMovement) ?? "") ?? .none
        windowRefreshInterval = (
            WindowRefreshInterval(rawValue: store.string(forKey: Key.windowRefreshInterval) ?? "")
                ?? .thirtySeconds
        ).normalized
        diagnosticsEnabled = store.bool(forKey: Key.diagnosticsEnabled) ?? false
        hasRequestedInputMonitoringPermission = store.bool(forKey: Key.requestedInputMonitoringPermission) ?? false
        hasRequestedScreenRecordingPermission = store.bool(forKey: Key.requestedScreenRecordingPermission) ?? false
        onboardingCompleted = store.bool(forKey: Key.onboardingCompleted) ?? false
        WindowDiagnosticLogging.isEnabled = diagnosticsEnabled
    }

    func restoreDefaults() {
        isPaused = false
        showsMenuBarIcon = true
        checksPermissionsAtLaunch = true
        confirmsOnModifierRelease = true
        shortcut = .defaultSwitcher
        confirmsWithReturn = true
        supportsArrowNavigation = true
        overlayLayout = .automatic
        layoutAppearances = OverlayLayoutAppearance.defaultsByLayout()
        persistLayoutAppearances()
        mirrorLegacyAppearanceKeys()
        onThumbnailVisibilityChange?(shouldCaptureThumbnails)
        showsSearchField = false
        showsKeyboardHint = true
        overlayPosition = .activeWindowDisplay
        fixedDisplayIdentifier = ""
        animationPreference = .system
        appearance = .system
        currentSpaceOnly = false
        currentDisplayOnly = false
        includesMinimizedWindows = true
        includesHiddenApplications = true
        includesDialogs = true
        includesUntitledWindows = true
        ignoredBundleIdentifiers = []
        sortOrder = .recent
        includesCurrentWindow = true
        selectsPreviousWindow = true
        groupsApplications = false
        restoresMinimizedWindows = true
        pointerMovement = .none
        windowRefreshInterval = .thirtySeconds
        diagnosticsEnabled = false
        hasRequestedInputMonitoringPermission = false
        hasRequestedScreenRecordingPermission = false
    }

    func setShowsThumbnailsForAllLayouts(_ enabled: Bool) {
        for layout in OverlayLayout.allCases {
            var appearance = layoutAppearances[layout] ?? .default
            appearance.showsThumbnails = enabled
            layoutAppearances[layout] = appearance
        }
        persistLayoutAppearances()
        mirrorLegacyAppearanceKeys()
        onThumbnailVisibilityChange?(shouldCaptureThumbnails)
    }

    private var currentLayoutAppearance: OverlayLayoutAppearance {
        layoutAppearances[overlayLayout] ?? .default
    }

    private func updateCurrentLayoutAppearance(_ body: (inout OverlayLayoutAppearance) -> Void) {
        var appearance = currentLayoutAppearance
        body(&appearance)
        layoutAppearances[overlayLayout] = appearance
        persistLayoutAppearances()
        mirrorLegacyAppearanceKeys()
    }

    private static func loadLayoutAppearances(from store: SettingsStoring) -> [OverlayLayout: OverlayLayoutAppearance] {
        let legacy = OverlayLayoutAppearance(
            cardSize: CardSize(rawValue: store.string(forKey: Key.cardSize) ?? "") ?? .medium,
            showsThumbnails: store.bool(forKey: Key.showsThumbnails) ?? true,
            showsApplicationName: store.bool(forKey: Key.showsApplicationName) ?? true,
            showsWindowTitle: store.bool(forKey: Key.showsWindowTitle) ?? true,
            showsWindowStatus: store.bool(forKey: Key.showsStatus) ?? true
        )
        let stored: [OverlayLayout: OverlayLayoutAppearance]
        if let data = store.data(forKey: Key.layoutAppearances),
           let decoded = try? JSONDecoder().decode([OverlayLayout: OverlayLayoutAppearance].self, from: data) {
            stored = decoded
        } else {
            stored = [:]
        }
        return OverlayLayout.allCases.reduce(into: [:]) { result, layout in
            result[layout] = stored[layout] ?? legacy
        }
    }

    private func persistLayoutAppearances() {
        if let data = try? JSONEncoder().encode(layoutAppearances) {
            save(data, for: Key.layoutAppearances)
        }
    }

    private func mirrorLegacyAppearanceKeys() {
        let appearance = currentLayoutAppearance
        save(appearance.cardSize.rawValue, for: Key.cardSize)
        save(appearance.showsThumbnails, for: Key.showsThumbnails)
        save(appearance.showsApplicationName, for: Key.showsApplicationName)
        save(appearance.showsWindowTitle, for: Key.showsWindowTitle)
        save(appearance.showsWindowStatus, for: Key.showsStatus)
    }

    private func save(_ value: Bool, for key: String) {
        store.set(value, forKey: key)
    }

    private func save(_ value: String, for key: String) {
        store.set(value, forKey: key)
    }

    private func save(_ value: [String], for key: String) {
        store.set(value, forKey: key)
    }

    private func save(_ value: Data, for key: String) {
        store.set(value, forKey: key)
    }
}

nonisolated struct WindowQueryOptions: Equatable, Sendable {
    let ignoredBundleIdentifiers: Set<String>
    let includesHiddenApplications: Bool
    let includesMinimizedWindows: Bool
    let includesDialogs: Bool
    let includesUntitledWindows: Bool
    let currentSpaceOnly: Bool
    let currentDisplayOnly: Bool
    let includesCurrentWindow: Bool
    let sortOrder: WindowSortOrder

    @MainActor
    init(settings: AppSettings) {
        ignoredBundleIdentifiers = settings.ignoredBundleIdentifiers
        includesHiddenApplications = settings.includesHiddenApplications
        includesMinimizedWindows = settings.includesMinimizedWindows
        includesDialogs = settings.includesDialogs
        includesUntitledWindows = settings.includesUntitledWindows
        currentSpaceOnly = settings.currentSpaceOnly
        currentDisplayOnly = settings.currentDisplayOnly
        includesCurrentWindow = settings.includesCurrentWindow
        sortOrder = settings.sortOrder
    }
}
