import CoreGraphics
import XCTest
@testable import TabFlow

final class ScreenshotModeTests: XCTestCase {
    func testParsesScreenshotModeAndScenario() {
        let configuration = ScreenshotModeConfiguration(arguments: [
            "tabflow",
            "--screenshot-mode",
            "--scenario",
            "window-preview"
        ])

        XCTAssertTrue(configuration.isEnabled)
        XCTAssertEqual(configuration.scenario, .windowPreview)
        XCTAssertEqual(configuration.initialSelection, 0)
        XCTAssertEqual(configuration.panelSize, CGSize(width: 1_200, height: 560))
    }

    func testParsesEqualsScenarioArgument() {
        let configuration = ScreenshotModeConfiguration(arguments: [
            "tabflow",
            "--screenshot-mode",
            "--scenario=window-list"
        ])

        XCTAssertTrue(configuration.isEnabled)
        XCTAssertEqual(configuration.scenario, .windowList)
        XCTAssertEqual(configuration.panelSize, CGSize(width: 640, height: 568))
    }

    func testParsesAppStoreScenarioAliases() {
        let first = ScreenshotModeConfiguration(arguments: [
            "tabflow", "--screenshot-mode", "--scenario", "app-store-01"
        ])
        let second = ScreenshotModeConfiguration(arguments: [
            "tabflow", "--screenshot-mode", "--scenario", "app-store-02"
        ])
        let third = ScreenshotModeConfiguration(arguments: [
            "tabflow", "--screenshot-mode", "--scenario", "app-store-03"
        ])

        XCTAssertEqual(first.scenario, .windowGrid)
        XCTAssertEqual(second.scenario, .windowList)
        XCTAssertEqual(third.scenario, .settings)
    }

    func testScreenshotModeExcludesHiddenAndMinimizedWindows() async {
        await MainActor.run {
            let suiteName = "com.dreace.tabflow.tests.ScreenshotMode.apply"
            guard let defaults = UserDefaults(suiteName: suiteName) else {
                XCTFail("Unable to create isolated defaults suite")
                return
            }
            defaults.removePersistentDomain(forName: suiteName)
            defer { defaults.removePersistentDomain(forName: suiteName) }

            let settings = AppSettings(store: UserDefaultsSettingsStore(defaults: defaults))
            XCTAssertTrue(settings.includesHiddenApplications)
            XCTAssertTrue(settings.includesMinimizedWindows)

            ScreenshotScenario.windowGrid.apply(to: settings)
            XCTAssertTrue(settings.includesHiddenApplications)
            XCTAssertFalse(settings.includesMinimizedWindows)
            XCTAssertEqual(settings.sortOrder, .application)
            XCTAssertEqual(settings.overlayLayout, .grid)

            ScreenshotScenario.windowList.apply(to: settings)
            XCTAssertEqual(settings.overlayLayout, .list)
            XCTAssertFalse(settings.showsThumbnails)
        }
    }

    func testFixtureBundleIdentifiersCoverScreenshotWindows() {
        XCTAssertTrue(ScreenshotModeConfiguration.fixtureBundleIdentifiers.contains("com.apple.finder"))
        XCTAssertTrue(ScreenshotModeConfiguration.fixtureBundleIdentifiers.contains("com.apple.Safari"))
        XCTAssertTrue(ScreenshotModeConfiguration.fixtureBundleIdentifiers.contains("com.apple.TextEdit"))
        XCTAssertTrue(ScreenshotModeConfiguration.fixtureBundleIdentifiers.contains("com.apple.Numbers"))
        XCTAssertFalse(ScreenshotModeConfiguration.fixtureBundleIdentifiers.contains("com.apple.Terminal"))
        XCTAssertFalse(ScreenshotModeConfiguration.fixtureBundleIdentifiers.contains("com.dreace.tabflow"))
    }

    func testScenarioFramesAndSelectionAreStable() {
        XCTAssertEqual(
            ScreenshotScenario.windowGrid.panelSize,
            CGSize(width: 1_200, height: 560)
        )
        XCTAssertEqual(ScreenshotScenario.windowGrid.initialSelection, 1)
        XCTAssertEqual(
            ScreenshotScenario.windowList.panelSize,
            CGSize(width: 640, height: 568)
        )
        XCTAssertNil(
            ScreenshotModeConfiguration(
                arguments: ["tabflow", "--screenshot-mode", "--scenario", "window-list"]
            ).panelOrigin
        )
        XCTAssertNil(
            ScreenshotModeConfiguration(
                arguments: ["tabflow", "--screenshot-mode", "--scenario", "window-grid"]
            ).panelOrigin
        )
    }

    func testListPanelCentersOnTheFullScreenFrame() {
        let frame = OverlayPanelPlacement.centeredFrame(
            size: CGSize(width: 640, height: 568),
            in: CGRect(x: 0, y: 0, width: 1_728, height: 956)
        )

        XCTAssertEqual(frame.origin.x, 544)
        XCTAssertEqual(frame.origin.y, 194)
        XCTAssertEqual(frame.size, CGSize(width: 640, height: 568))
    }
}
