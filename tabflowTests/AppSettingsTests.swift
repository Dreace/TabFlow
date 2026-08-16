import XCTest
@testable import TabFlow

final class AppSettingsTests: XCTestCase {
    nonisolated func testDefaultsAndChangesUseInjectedStore() async {
        await MainActor.run {
            let suiteName = "com.dreace.tabflow.tests.AppSettings"
            guard let defaults = UserDefaults(suiteName: suiteName) else {
                XCTFail("Unable to create isolated defaults suite")
                return
            }
            defaults.removePersistentDomain(forName: suiteName)
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let store = UserDefaultsSettingsStore(defaults: defaults)
            let settings = AppSettings(store: store)

            XCTAssertTrue(settings.includesMinimizedWindows)
            XCTAssertTrue(settings.includesUntitledWindows)
            XCTAssertTrue(settings.showsKeyboardHint)
            XCTAssertTrue(settings.confirmsOnModifierRelease)
            XCTAssertEqual(settings.overlayLayout, .automatic)
            XCTAssertEqual(settings.fixedDisplayIdentifier, "")
            XCTAssertFalse(settings.showsSearchField)
            XCTAssertEqual(settings.windowRefreshInterval, .thirtySeconds)
            XCTAssertEqual(WindowRefreshInterval.thirtySeconds.duration, .seconds(30))
            XCTAssertFalse(settings.hasRequestedInputMonitoringPermission)
            XCTAssertFalse(settings.hasRequestedScreenRecordingPermission)

            settings.includesMinimizedWindows = false
            settings.fixedDisplayIdentifier = "42"
            settings.hasRequestedInputMonitoringPermission = true
            settings.hasRequestedScreenRecordingPermission = true
            settings.showsSearchField = true
            settings.windowRefreshInterval = .tenSeconds
            settings.ignoredBundleIdentifiers = ["com.example.ignored"]
            var appearanceDidChange = false
            settings.onAppearanceChange = { appearanceDidChange = true }
            settings.appearance = .dark
            XCTAssertTrue(appearanceDidChange)

            let reloaded = AppSettings(store: store)
            XCTAssertFalse(reloaded.includesMinimizedWindows)
            XCTAssertEqual(reloaded.fixedDisplayIdentifier, "42")
            XCTAssertTrue(reloaded.hasRequestedInputMonitoringPermission)
            XCTAssertTrue(reloaded.hasRequestedScreenRecordingPermission)
            XCTAssertTrue(reloaded.showsSearchField)
            XCTAssertEqual(reloaded.windowRefreshInterval, .tenSeconds)
            XCTAssertEqual(reloaded.ignoredBundleIdentifiers, ["com.example.ignored"])
            XCTAssertEqual(reloaded.appearance, .dark)
        }
    }

    nonisolated func testGroupingKeepsRecentSortOrder() async {
        await MainActor.run {
            let suiteName = "com.dreace.tabflow.tests.AppSettings.groupingSort"
            guard let defaults = UserDefaults(suiteName: suiteName) else {
                XCTFail("Unable to create isolated defaults suite")
                return
            }
            defaults.removePersistentDomain(forName: suiteName)
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let settings = AppSettings(store: UserDefaultsSettingsStore(defaults: defaults))
            settings.sortOrder = .recent
            settings.groupsApplications = true

            let options = WindowQueryOptions(settings: settings)
            XCTAssertEqual(options.sortOrder, .recent)
        }
    }

    nonisolated func testLegacyLayoutMigratesAndDisablingThumbnailsNotifiesOwner() async {
        await MainActor.run {
            let suiteName = "com.dreace.tabflow.tests.AppSettings.layout"
            guard let defaults = UserDefaults(suiteName: suiteName) else {
                XCTFail("Unable to create isolated defaults suite")
                return
            }
            defaults.removePersistentDomain(forName: suiteName)
            defer { defaults.removePersistentDomain(forName: suiteName) }

            defaults.set("horizontal", forKey: "layout")
            let settings = AppSettings(store: UserDefaultsSettingsStore(defaults: defaults))
            XCTAssertEqual(settings.overlayLayout, .horizontal)

            var thumbnailVisibility: Bool?
            settings.onThumbnailVisibilityChange = { thumbnailVisibility = $0 }
            settings.showsThumbnails = false
            XCTAssertEqual(thumbnailVisibility, false)

            var intervalDidChange = false
            settings.onWindowRefreshIntervalChange = { intervalDidChange = true }
            settings.windowRefreshInterval = .fiveSeconds
            XCTAssertTrue(intervalDidChange)

            defaults.set("automatic", forKey: "layout")
            let migratedAutomaticLayout = AppSettings(store: UserDefaultsSettingsStore(defaults: defaults))
            XCTAssertEqual(migratedAutomaticLayout.overlayLayout, .automatic)

            defaults.set("oneSecond", forKey: "windowRefreshInterval")
            let migratedInterval = AppSettings(store: UserDefaultsSettingsStore(defaults: defaults))
            XCTAssertEqual(migratedInterval.windowRefreshInterval, .fiveSeconds)
        }
    }

    func testSettingsSectionTitlesResolveLocalizedValues() {
        for section in SettingsSection.allCases {
            XCTAssertFalse(section.title.isEmpty)
            XCTAssertNotEqual(section.title, "settings.section.\(section.rawValue)")
        }
    }

    nonisolated func testLayoutAppearanceSettingsAreStoredSeparately() async {
        await MainActor.run {
            let suiteName = "com.dreace.tabflow.tests.AppSettings.layoutAppearance"
            guard let defaults = UserDefaults(suiteName: suiteName) else {
                XCTFail("Unable to create isolated defaults suite")
                return
            }
            defaults.removePersistentDomain(forName: suiteName)
            defer { defaults.removePersistentDomain(forName: suiteName) }

            let settings = AppSettings(store: UserDefaultsSettingsStore(defaults: defaults))
            settings.overlayLayout = .grid
            settings.cardSize = .large
            settings.showsThumbnails = false
            settings.showsApplicationName = false
            settings.showsWindowTitle = true
            settings.showsWindowStatus = false

            settings.overlayLayout = .list
            XCTAssertEqual(settings.cardSize, .medium)
            XCTAssertTrue(settings.showsThumbnails)
            XCTAssertTrue(settings.showsApplicationName)
            XCTAssertTrue(settings.showsWindowTitle)
            XCTAssertTrue(settings.showsWindowStatus)
            XCTAssertFalse(settings.shouldCaptureThumbnails)
            settings.showsApplicationName = false
            settings.showsWindowStatus = false

            settings.overlayLayout = .grid
            XCTAssertEqual(settings.cardSize, .large)
            XCTAssertFalse(settings.showsThumbnails)
            XCTAssertFalse(settings.showsApplicationName)
            XCTAssertTrue(settings.showsWindowTitle)
            XCTAssertFalse(settings.showsWindowStatus)
            XCTAssertFalse(settings.shouldCaptureThumbnails)

            let reloaded = AppSettings(store: UserDefaultsSettingsStore(defaults: defaults))
            XCTAssertEqual(reloaded.overlayLayout, .grid)
            XCTAssertEqual(reloaded.cardSize, .large)
            XCTAssertFalse(reloaded.showsThumbnails)
            reloaded.overlayLayout = .list
            XCTAssertFalse(reloaded.showsApplicationName)
            XCTAssertFalse(reloaded.showsWindowStatus)
        }
    }

    nonisolated func testLegacyAppearanceSettingsMigrateToEveryLayout() async {
        await MainActor.run {
            let suiteName = "com.dreace.tabflow.tests.AppSettings.legacyAppearance"
            guard let defaults = UserDefaults(suiteName: suiteName) else {
                XCTFail("Unable to create isolated defaults suite")
                return
            }
            defaults.removePersistentDomain(forName: suiteName)
            defer { defaults.removePersistentDomain(forName: suiteName) }

            defaults.set("small", forKey: "cardSize")
            defaults.set(false, forKey: "showsThumbnails")
            defaults.set(false, forKey: "showsApplicationName")
            let settings = AppSettings(store: UserDefaultsSettingsStore(defaults: defaults))
            XCTAssertEqual(settings.cardSize, .small)
            XCTAssertFalse(settings.showsThumbnails)
            XCTAssertFalse(settings.showsApplicationName)

            settings.overlayLayout = .horizontal
            XCTAssertEqual(settings.cardSize, .small)
            XCTAssertFalse(settings.showsThumbnails)
            XCTAssertFalse(settings.showsApplicationName)
        }
    }

    func testListLayoutHidesCardSizeAndThumbnails() {
        XCTAssertTrue(OverlayLayoutAppearanceSupport.supportsCardSize(.automatic))
        XCTAssertTrue(OverlayLayoutAppearanceSupport.supportsCardSize(.horizontal))
        XCTAssertTrue(OverlayLayoutAppearanceSupport.supportsCardSize(.grid))
        XCTAssertFalse(OverlayLayoutAppearanceSupport.supportsCardSize(.list))
        XCTAssertTrue(OverlayLayoutAppearanceSupport.supportsThumbnails(.grid))
        XCTAssertFalse(OverlayLayoutAppearanceSupport.supportsThumbnails(.list))
    }

    nonisolated func testDisablingThumbnailsForAllLayoutsClearsCaptureFlag() async {
        await MainActor.run {
            let suiteName = "com.dreace.tabflow.tests.AppSettings.allThumbnails"
            guard let defaults = UserDefaults(suiteName: suiteName) else {
                XCTFail("Unable to create isolated defaults suite")
                return
            }
            defaults.removePersistentDomain(forName: suiteName)
            defer { defaults.removePersistentDomain(forName: suiteName) }

            let settings = AppSettings(store: UserDefaultsSettingsStore(defaults: defaults))
            settings.overlayLayout = .grid
            settings.showsThumbnails = true
            XCTAssertTrue(settings.showsThumbnailsInAnySupportedLayout)
            settings.setShowsThumbnailsForAllLayouts(false)
            XCTAssertFalse(settings.showsThumbnails)
            XCTAssertFalse(settings.shouldCaptureThumbnails)
            XCTAssertFalse(settings.showsThumbnailsInAnySupportedLayout)
            settings.overlayLayout = .automatic
            XCTAssertFalse(settings.showsThumbnails)
        }
    }
}
