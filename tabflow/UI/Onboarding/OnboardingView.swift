import Observation
import SwiftUI

@MainActor
@Observable
final class ShortcutProbeState {
    var recognized = false
}

struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case welcome
        case accessibility
        case shortcut
        case thumbnails
        case completed
    }

    @Bindable var settings: AppSettings
    @Bindable var permissions: PermissionManager
    @Bindable var shortcutProbe: ShortcutProbeState
    let onShortcutProbeActive: (Bool) -> Void
    let onComplete: () -> Void
    let onOpenSettings: () -> Void

    @State private var step: Step = .welcome

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: stepIcon)
                .font(.system(size: 52))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(verbatim: stepTitle)
                    .font(.largeTitle.bold())
                Text(verbatim: stepDescription)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 480)
            }

            Spacer()

            actionContent

            HStack {
                if step != .welcome {
                    Button("action.back") {
                        moveBack()
                    }
                }
                Spacer()
                if step != .completed {
                    Button("action.later") {
                        advance()
                    }
                }
            }
        }
        .padding(36)
        .frame(width: 620, height: 440)
        .onChange(of: step) { _, newStep in
            updateShortcutProbe(for: newStep)
        }
        .onChange(of: settings.shortcut) { _, _ in
            shortcutProbe.recognized = false
        }
        .onDisappear {
            onShortcutProbeActive(false)
        }
    }

    @ViewBuilder
    private var actionContent: some View {
        switch step {
        case .welcome:
            Button("onboarding.start") {
                advance()
            }
            .buttonStyle(.borderedProminent)
            Button("action.later", action: onComplete)
        case .accessibility:
            HStack {
                Button("permissions.openAccessibility") {
                    permissions.requestAccessibility()
                    permissions.openAccessibilitySettings()
                }
                Button("permissions.refresh") {
                    permissions.refresh()
                    if permissions.accessibility == .granted {
                        advance()
                    }
                }
            }
        case .shortcut:
            shortcutProbeContent
        case .thumbnails:
            HStack {
                Button("onboarding.enableThumbnails") {
                    settings.setShowsThumbnailsForAllLayouts(true)
                    settings.hasRequestedScreenRecordingPermission = true
                    permissions.requestScreenRecording()
                    advance()
                }
                .buttonStyle(.borderedProminent)
                Button("onboarding.disableThumbnails") {
                    settings.setShowsThumbnailsForAllLayouts(false)
                    advance()
                }
            }
        case .completed:
            HStack {
                Button("onboarding.useNow") {
                    settings.onboardingCompleted = true
                    onComplete()
                }
                .buttonStyle(.borderedProminent)
                Button("onboarding.openSettings") {
                    settings.onboardingCompleted = true
                    onComplete()
                    onOpenSettings()
                }
            }
        }
    }

    private var shortcutProbeContent: some View {
        let status = shortcutProbeStatus
        return VStack(spacing: 12) {
            Text(settings.shortcut.displayName)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
            Label(shortcutStatusText(status), systemImage: shortcutStatusSymbol(status))
                .foregroundStyle(shortcutStatusTint(status))
            ShortcutRecorder(shortcut: $settings.shortcut)
                .frame(width: 170)
            HStack {
                Button("onboarding.shortcut.retest") {
                    shortcutProbe.recognized = false
                    onShortcutProbeActive(true)
                }
                Button("action.continue") {
                    advance()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!OnboardingShortcutProbe.canContinue(status))
            }
        }
    }

    private var shortcutProbeStatus: OnboardingShortcutProbe.Status {
        OnboardingShortcutProbe.status(
            hasSystemConflict: settings.shortcut.hasKnownSystemConflict,
            eventTapAvailable: permissions.eventTapAvailable,
            didRecognizeShortcut: shortcutProbe.recognized
        )
    }

    private var stepIcon: String {
        switch step {
        case .welcome: "rectangle.on.rectangle.angled"
        case .accessibility: "accessibility"
        case .shortcut: "keyboard"
        case .thumbnails: "photo.on.rectangle"
        case .completed: "checkmark.circle"
        }
    }

    private var stepTitle: String {
        switch step {
        case .welcome: String(localized: "onboarding.welcome.title")
        case .accessibility: String(localized: "onboarding.accessibility.title")
        case .shortcut: String(localized: "onboarding.shortcut.title")
        case .thumbnails: String(localized: "onboarding.thumbnails.title")
        case .completed: String(localized: "onboarding.completed.title")
        }
    }

    private var stepDescription: String {
        switch step {
        case .welcome: String(localized: "onboarding.welcome.description")
        case .accessibility: String(localized: "onboarding.accessibility.description")
        case .shortcut: String(localized: "onboarding.shortcut.description")
        case .thumbnails: String(localized: "onboarding.thumbnails.description")
        case .completed: String(localized: "onboarding.completed.description")
        }
    }

    private func shortcutStatusText(_ status: OnboardingShortcutProbe.Status) -> String {
        switch status {
        case .waiting: String(localized: "onboarding.shortcut.waiting")
        case .succeeded: String(localized: "onboarding.shortcut.succeeded")
        case .conflict: String(localized: "onboarding.shortcut.conflict")
        case .unavailable: String(localized: "onboarding.shortcut.unavailable")
        }
    }

    private func shortcutStatusSymbol(_ status: OnboardingShortcutProbe.Status) -> String {
        switch status {
        case .waiting: "keyboard"
        case .succeeded: "checkmark.circle.fill"
        case .conflict: "exclamationmark.triangle.fill"
        case .unavailable: "xmark.circle.fill"
        }
    }

    private func shortcutStatusTint(_ status: OnboardingShortcutProbe.Status) -> Color {
        switch status {
        case .waiting: .secondary
        case .succeeded: .green
        case .conflict, .unavailable: .orange
        }
    }

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    private func moveBack() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    private func updateShortcutProbe(for step: Step) {
        let isShortcutStep = step == .shortcut
        if isShortcutStep {
            shortcutProbe.recognized = false
        }
        onShortcutProbeActive(isShortcutStep)
    }
}
