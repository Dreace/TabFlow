import AppKit
import Observation
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case shortcuts
    case appearance
    case windowScope
    case behavior
    case permissions
    case privacy
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .general: String(localized: "settings.section.general")
        case .shortcuts: String(localized: "settings.section.shortcuts")
        case .appearance: String(localized: "settings.section.appearance")
        case .windowScope: String(localized: "settings.section.windowScope")
        case .behavior: String(localized: "settings.section.behavior")
        case .permissions: String(localized: "settings.section.permissions")
        case .privacy: String(localized: "settings.section.privacy")
        case .about: String(localized: "settings.section.about")
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .shortcuts: "keyboard"
        case .appearance: "paintbrush"
        case .windowScope: "rectangle.3.group"
        case .behavior: "arrow.left.arrow.right"
        case .permissions: "lock.shield"
        case .privacy: "hand.raised"
        case .about: "info.circle"
        }
    }
}

@MainActor
@Observable
final class SettingsViewModel {
    struct DisplayOption: Identifiable, Equatable {
        let id: String
        let name: String
    }

    enum AboutSheet: String, Identifiable {
        case help

        var id: Self { self }
    }

    var settings: AppSettings
    let permissions: PermissionManager
    var selectedSection: SettingsSection = .general
    var errorMessage: String?
    var activationFailureMessage: String?
    var confirmsReset = false
    var confirmsHideMenuBar = false
    var isLaunchAtLoginEnabled = false
    var availableDisplays: [DisplayOption] = []
    var activeAboutSheet: AboutSheet?
    var showsDiagnosticPreview = false
    var diagnosticReport = ""

    private let onMenuBarVisibilityChanged: (Bool) -> Void
    private let onClearThumbnails: () -> Void

    init(
        settings: AppSettings,
        permissions: PermissionManager,
        onMenuBarVisibilityChanged: @escaping (Bool) -> Void,
        onClearThumbnails: @escaping () -> Void
    ) {
        self.settings = settings
        self.permissions = permissions
        self.onMenuBarVisibilityChanged = onMenuBarVisibilityChanged
        self.onClearThumbnails = onClearThumbnails
        isLaunchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        refreshAvailableDisplays()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            isLaunchAtLoginEnabled = enabled
        } catch {
            errorMessage = error.localizedDescription
            isLaunchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        }
    }

    func setMenuBarVisible(_ visible: Bool) {
        if visible {
            settings.showsMenuBarIcon = true
            onMenuBarVisibilityChanged(true)
        } else {
            confirmsHideMenuBar = true
        }
    }

    func confirmHideMenuBar() {
        settings.showsMenuBarIcon = false
        onMenuBarVisibilityChanged(false)
    }

    func addIgnoredApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        let identifiers = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        settings.ignoredBundleIdentifiers.formUnion(identifiers)
    }

    func clearThumbnails() {
        onClearThumbnails()
    }

    var shortcutStatus: (text: String, systemImage: String, tint: NSColor)? {
        if settings.shortcut.hasKnownSystemConflict {
            return (
                String(localized: "settings.shortcuts.systemConflict"),
                "exclamationmark.triangle.fill",
                .systemOrange
            )
        }
        if !permissions.eventTapAvailable {
            return (
                String(localized: "settings.shortcuts.availabilityUnknown"),
                "questionmark.circle",
                .secondaryLabelColor
            )
        }
        return nil
    }

    func refreshAvailableDisplays() {
        availableDisplays = NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            return DisplayOption(id: number.stringValue, name: screen.localizedName)
        }
    }

    func prepareDiagnosticExport() {
        diagnosticReport = DiagnosticReportBuilder.make(settings: settings, permissions: permissions)
        showsDiagnosticPreview = true
    }

    func exportDiagnosticReport() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "TabFlow-Diagnostics.txt"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(diagnosticReport.utf8).write(to: url, options: .atomic)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
