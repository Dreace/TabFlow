import AppKit
import Foundation

@MainActor
enum DiagnosticReportBuilder {
    static func make(settings: AppSettings, permissions: PermissionManager, now: Date = .now) -> String {
        let formatter = ISO8601DateFormatter()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return [
            "TabFlow diagnostic report",
            "Generated: \(formatter.string(from: now))",
            "Version: \(version) (\(build))",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Displays: \(NSScreen.screens.count)",
            "Accessibility permission: \(permissionText(permissions.accessibility))",
            "Input Monitoring permission: \(permissionText(permissions.inputMonitoring))",
            "Screen Recording permission: \(permissionText(permissions.screenRecording))",
            "Event tap available: \(settingsValue(permissions.eventTapAvailable))",
            "Thumbnails enabled: \(settingsValue(settings.shouldCaptureThumbnails))",
            "Window sort order: \(settings.sortOrder.rawValue)",
            "Current-window inclusion: \(settingsValue(settings.includesCurrentWindow))",
            "Ignored-application count: \(settings.ignoredBundleIdentifiers.count)",
            "Diagnostic logging enabled: \(settingsValue(settings.diagnosticsEnabled))",
            "",
            "This report does not contain window titles, window images, document paths, or typed text."
        ].joined(separator: "\n")
    }

    private static func permissionText(_ state: PermissionState) -> String {
        switch state {
        case .granted: "granted"
        case .denied: "denied"
        case .unavailable: "unavailable"
        }
    }

    private static func settingsValue(_ value: Bool) -> String {
        value ? "enabled" : "disabled"
    }
}
