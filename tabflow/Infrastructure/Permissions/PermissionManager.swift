import ApplicationServices
import AppKit
import CoreGraphics
import Foundation
import Observation

enum PermissionState {
    case granted
    case denied
    case unavailable
}

nonisolated enum AccessibilityTrustReading {
    static let apiChangeNotification = Notification.Name("com.apple.accessibility.api")

    /// `com.apple.accessibility.api` does not include the new TCC value.
    /// Reading `AXIsProcessTrusted` in that callback returns the previous value,
    /// which after a toggle is the opposite of System Settings.
    static let settleDelays: [Duration] = [
        .milliseconds(100),
        .milliseconds(500),
        .seconds(1)
    ]

    static func isGranted(processTrusted: Bool, systemWideAttributeError: AXError) -> Bool {
        switch systemWideAttributeError {
        case .apiDisabled:
            return false
        case .success:
            return true
        default:
            return processTrusted
        }
    }

    static func systemWideProbeError() -> AXError {
        let element = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(element, 0.05)
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
    }
}

@MainActor
@Observable
final class PermissionManager {
    private(set) var accessibility: PermissionState = .denied
    private(set) var inputMonitoring: PermissionState = .denied
    private(set) var screenRecording: PermissionState = .denied
    private(set) var eventTapAvailable = false

    private var accessibilityChangeGeneration = 0

    var hasCorePermission: Bool {
        accessibility == .granted
    }

    func refresh() {
        accessibility = AccessibilityTrustReading.isGranted(
            processTrusted: accessibilityIsGranted(prompting: false),
            systemWideAttributeError: AccessibilityTrustReading.systemWideProbeError()
        ) ? .granted : .denied
        inputMonitoring = CGPreflightListenEventAccess() ? .granted : .denied
        screenRecording = CGPreflightScreenCaptureAccess() ? .granted : .denied
    }

    func refreshAfterAccessibilityAPIChange() async {
        accessibilityChangeGeneration += 1
        let generation = accessibilityChangeGeneration
        for delay in AccessibilityTrustReading.settleDelays {
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard generation == accessibilityChangeGeneration else { return }
            refresh()
        }
    }

    func cancelPendingAccessibilityRefresh() {
        accessibilityChangeGeneration += 1
    }

    func requestAccessibility() {
        _ = accessibilityIsGranted(prompting: true)
        refresh()
    }

    func requestInputMonitoring() {
        inputMonitoring = CGRequestListenEventAccess() ? .granted : .denied
    }

    func requestScreenRecording() {
        screenRecording = CGRequestScreenCaptureAccess() ? .granted : .denied
    }

    func setEventTapAvailable(_ available: Bool) {
        eventTapAvailable = available
        if !available, inputMonitoring == .granted {
            inputMonitoring = .unavailable
        }
    }

    func openAccessibilitySettings() {
        openSystemSettings(anchor: "Privacy_Accessibility")
    }

    func openInputMonitoringSettings() {
        requestInputMonitoring()
        openSystemSettings(anchor: "Privacy_ListenEvent")
    }

    func openScreenRecordingSettings() {
        requestScreenRecording()
        openSystemSettings(anchor: "Privacy_ScreenCapture")
    }

    private func openSystemSettings(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func accessibilityIsGranted(prompting: Bool) -> Bool {
        if prompting {
            let options = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
        return AXIsProcessTrusted()
    }
}
