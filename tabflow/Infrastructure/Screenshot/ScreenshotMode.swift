import CoreGraphics
import Foundation

enum ScreenshotScenario: String, CaseIterable, Sendable {
    case windowGrid = "window-grid"
    case windowPreview = "window-preview"
    case windowList = "window-list"
    case settings

    var panelSize: CGSize? {
        switch self {
        case .windowGrid, .windowPreview:
            CGSize(width: 1_200, height: 560)
        case .windowList:
            CGSize(width: 640, height: 568)
        case .settings:
            nil
        }
    }

    var initialSelection: Int? {
        switch self {
        case .windowGrid:
            1
        case .windowPreview, .windowList, .settings:
            0
        }
    }

    @MainActor
    func apply(to settings: AppSettings) {
        // Screenshot mode is an explicit automation entry point. It must not
        // stop on first-run onboarding or a launch-time permission gate; the
        // VM is prepared and authorized before the capture step.
        settings.onboardingCompleted = true
        settings.checksPermissionsAtLaunch = false
        settings.showsSearchField = false
        settings.showsApplicationName = true
        settings.showsWindowTitle = true
        settings.showsWindowStatus = false
        settings.groupsApplications = false
        settings.overlayPosition = .mainDisplay
        settings.appearance = .light
        settings.animationPreference = .none
        settings.sortOrder = .application
        settings.selectsPreviousWindow = false
        settings.includesHiddenApplications = true
        settings.includesMinimizedWindows = false

        switch self {
        case .windowGrid:
            settings.overlayLayout = .grid
            settings.cardSize = .medium
            settings.showsThumbnails = true
        case .windowPreview:
            settings.overlayLayout = .grid
            settings.cardSize = .large
            settings.showsThumbnails = true
        case .windowList:
            settings.overlayLayout = .list
            settings.cardSize = .medium
            settings.showsThumbnails = false
        case .settings:
            settings.overlayLayout = .grid
            settings.cardSize = .medium
            settings.showsThumbnails = true
        }
    }
}

struct ScreenshotModeConfiguration: Sendable {
    let isEnabled: Bool
    let scenario: ScreenshotScenario

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        isEnabled = arguments.contains("--screenshot-mode")

        let scenarioArgument: String?
        if let index = arguments.firstIndex(of: "--scenario"), arguments.indices.contains(index + 1) {
            scenarioArgument = arguments[index + 1]
        } else {
            scenarioArgument = arguments.first { argument in
                argument.hasPrefix("--scenario=")
            }?.replacingOccurrences(of: "--scenario=", with: "")
        }
        switch scenarioArgument {
        case "app-store-01":
            scenario = .windowGrid
        case "app-store-02":
            scenario = .windowList
        case "app-store-03":
            scenario = .settings
        default:
            scenario = ScreenshotScenario(rawValue: scenarioArgument ?? "") ?? .windowGrid
        }
    }

    /// Fixture apps used in App Store captures. Screenshot mode hides everything else,
    /// including Terminal windows created by the capture script.
    static let fixtureBundleIdentifiers: Set<String> = [
        "com.apple.finder",
        "com.apple.Safari",
        "com.apple.TextEdit",
        "com.apple.Preview",
        "com.apple.Numbers",
        "com.apple.iWork.Numbers"
    ]

    var panelSize: CGSize? {
        guard isEnabled else { return nil }
        return scenario.panelSize
    }

    var panelOrigin: CGPoint? {
        nil
    }

    var initialSelection: Int? {
        guard isEnabled else { return nil }
        return scenario.initialSelection
    }
}
