import CoreGraphics
import XCTest
@testable import TabFlow

@MainActor
final class SwitcherCoordinatorTests: XCTestCase {
    func testCachedWindowsArePresentedBeforeAsynchronousRefreshCompletes() async {
        let cachedWindow = window(1, title: "Cached", isCurrent: true)
        let refreshedWindow = window(2, title: "Refreshed", isCurrent: true)
        let provider = WindowProviderStub(cached: [cachedWindow], refreshed: [refreshedWindow])
        let overlay = OverlaySpy()
        let firstPresentation = expectation(description: "cached windows are presented")
        let refreshUpdate = expectation(description: "refreshed windows are merged")
        overlay.onShow = { firstPresentation.fulfill() }
        let suiteName = "com.dreace.tabflow.tests.SwitcherCoordinator"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: UserDefaultsSettingsStore(defaults: defaults))
        settings.selectsPreviousWindow = false
        let coordinator = SwitcherCoordinator(
            windows: provider,
            activator: WindowActivatorStub(),
            thumbnails: ThumbnailProviderStub(),
            overlay: overlay,
            settings: settings
        )

        coordinator.begin(direction: .forward)
        await fulfillment(of: [firstPresentation], timeout: 1)
        XCTAssertEqual(overlay.presentedSessions.last?.windows.map(\.id), [cachedWindow.id])
        XCTAssertFalse(coordinator.hasSearchQuery)

        coordinator.updateSearch("Cached")
        XCTAssertTrue(coordinator.hasSearchQuery)
        coordinator.clearSearch()
        XCTAssertFalse(coordinator.hasSearchQuery)
        overlay.onUpdate = { refreshUpdate.fulfill() }

        await provider.completeRefresh()
        await fulfillment(of: [refreshUpdate], timeout: 1)
        XCTAssertEqual(overlay.updatedSessions.last?.windows.map(\.id), [refreshedWindow.id])
        XCTAssertEqual(overlay.showLoadingCount, 0)
    }

    func testEmptyWindowListStaysVisibleUntilCancel() async {
        let provider = WindowProviderStub(cached: [], refreshed: [])
        let overlay = OverlaySpy()
        let emptyState = expectation(description: "empty overlay is shown")
        overlay.onShowNoWindows = { emptyState.fulfill() }
        let suiteName = "com.dreace.tabflow.tests.SwitcherCoordinator.EmptyState"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: UserDefaultsSettingsStore(defaults: defaults))
        let coordinator = SwitcherCoordinator(
            windows: provider,
            activator: WindowActivatorStub(),
            thumbnails: ThumbnailProviderStub(),
            overlay: overlay,
            settings: settings
        )
        var visibilityChanges: [Bool] = []
        coordinator.onVisibilityChange = { visibilityChanges.append($0) }

        coordinator.begin(direction: .forward)
        await provider.completeRefresh()
        await fulfillment(of: [emptyState], timeout: 1)

        XCTAssertTrue(coordinator.isVisible)
        XCTAssertEqual(overlay.showLoadingCount, 0)
        XCTAssertEqual(overlay.showNoWindowsCount, 1)
        XCTAssertEqual(visibilityChanges.last, true)

        coordinator.cancel()
        XCTAssertFalse(coordinator.isVisible)
        XCTAssertEqual(visibilityChanges.last, false)
    }

    func testCommitPolicyWaitsWhileOpeningWithoutASession() {
        XCTAssertEqual(
            SwitcherCommitPolicy.action(hasSelectedWindow: true, isOpening: true),
            .activate
        )
        XCTAssertEqual(
            SwitcherCommitPolicy.action(hasSelectedWindow: false, isOpening: true),
            .waitForSession
        )
        XCTAssertEqual(
            SwitcherCommitPolicy.action(hasSelectedWindow: false, isOpening: false),
            .cancel
        )
    }

    func testCommitDuringColdCacheOpenActivatesWhenRefreshCompletes() async {
        let current = window(1, title: "Current", isCurrent: true)
        let previous = window(2, title: "Previous", isCurrent: false)
        let provider = WindowProviderStub(cached: [], refreshed: [current, previous])
        let overlay = OverlaySpy()
        let activated = expectation(description: "pending commit activates the selected window")
        let activator = WindowActivatorStub()
        activator.onActivate = {
            if activator.activatedIDs.count == 2 {
                activated.fulfill()
            }
        }
        let suiteName = "com.dreace.tabflow.tests.SwitcherCoordinator.PendingCommit"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: UserDefaultsSettingsStore(defaults: defaults))
        XCTAssertTrue(settings.selectsPreviousWindow)
        let coordinator = SwitcherCoordinator(
            windows: provider,
            activator: activator,
            thumbnails: ThumbnailProviderStub(),
            overlay: overlay,
            settings: settings
        )

        coordinator.begin(direction: .forward)
        coordinator.commit()
        XCTAssertTrue(coordinator.isVisible)
        XCTAssertTrue(activator.activatedIDs.isEmpty)
        XCTAssertEqual(overlay.showLoadingCount, 0)

        await provider.completeRefresh()
        await fulfillment(of: [activated], timeout: 1)
        XCTAssertEqual(activator.activatedIDs, [previous.id, previous.id])
        XCTAssertFalse(coordinator.isVisible)
        XCTAssertGreaterThanOrEqual(overlay.hideCount, 1)
    }

    func testCommitHidesOverlayBeforeActivationCompletes() async {
        let current = window(1, title: "Current", isCurrent: true)
        let previous = window(2, title: "Previous", isCurrent: false)
        let provider = WindowProviderStub(cached: [current, previous], refreshed: [current, previous])
        let overlay = OverlaySpy()
        let firstPresentation = expectation(description: "cached windows are presented")
        overlay.onShow = { firstPresentation.fulfill() }
        let activated = expectation(description: "selected window is activated")
        let activator = WindowActivatorStub()
        var hideCountDuringFirstActivate = -1
        activator.onActivate = {
            if activator.activatedIDs.count == 1 {
                hideCountDuringFirstActivate = overlay.hideCount
            }
            if activator.activatedIDs.count == 2 {
                activated.fulfill()
            }
        }
        let suiteName = "com.dreace.tabflow.tests.SwitcherCoordinator.HideBeforeActivate"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: UserDefaultsSettingsStore(defaults: defaults))
        let coordinator = SwitcherCoordinator(
            windows: provider,
            activator: activator,
            thumbnails: ThumbnailProviderStub(),
            overlay: overlay,
            settings: settings
        )

        coordinator.begin(direction: .forward)
        await fulfillment(of: [firstPresentation], timeout: 1)
        coordinator.commit()
        await fulfillment(of: [activated], timeout: 1)

        XCTAssertGreaterThanOrEqual(hideCountDuringFirstActivate, 1)
        XCTAssertGreaterThanOrEqual(overlay.hideCount, 1)
        XCTAssertEqual(activator.activatedIDs, [previous.id, previous.id])
    }

    func testActivationFailureKeepsOverlayVisibleAndAllowsRetry() async {
        let current = window(1, title: "Current", isCurrent: true)
        let previous = window(2, title: "Previous", isCurrent: false)
        let provider = WindowProviderStub(cached: [current, previous], refreshed: [current, previous])
        let overlay = OverlaySpy()
        let shown = expectation(description: "cached windows are presented")
        overlay.onShow = { shown.fulfill() }
        let failed = expectation(description: "activation failure is shown")
        overlay.onShowActivationFailure = { failed.fulfill() }
        let activator = WindowActivatorStub()
        activator.remainingFailures = 1
        let suiteName = "com.dreace.tabflow.tests.SwitcherCoordinator.ActivationFailure"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: UserDefaultsSettingsStore(defaults: defaults))
        let coordinator = SwitcherCoordinator(
            windows: provider,
            activator: activator,
            thumbnails: ThumbnailProviderStub(),
            overlay: overlay,
            settings: settings
        )
        var failureMessages: [String] = []
        coordinator.onActivationFailure = { failureMessages.append($0) }

        coordinator.begin(direction: .forward)
        await fulfillment(of: [shown], timeout: 1)
        overlay.onShow = nil
        coordinator.commit()
        await fulfillment(of: [failed], timeout: 1)

        XCTAssertGreaterThanOrEqual(overlay.hideCount, 1)
        XCTAssertEqual(overlay.activationFailureMessages.count, 1)
        XCTAssertFalse(failureMessages.isEmpty)
        XCTAssertTrue(coordinator.isVisible)
        XCTAssertEqual(activator.activatedIDs, [previous.id])

        let retried = expectation(description: "retry activates and refocuses")
        activator.onActivate = {
            if activator.activatedIDs.count == 3 {
                retried.fulfill()
            }
        }
        coordinator.retryActivation()
        await fulfillment(of: [retried], timeout: 1)

        XCTAssertGreaterThanOrEqual(overlay.hideCount, 1)
        XCTAssertFalse(coordinator.isVisible)
        XCTAssertEqual(activator.activatedIDs, [previous.id, previous.id, previous.id])
    }

    func testRemoveFailedWindowKeepsRemainingWindowsVisible() async {
        let current = window(1, title: "Current", isCurrent: true)
        let previous = window(2, title: "Previous", isCurrent: false)
        let provider = WindowProviderStub(cached: [current, previous], refreshed: [current, previous])
        let overlay = OverlaySpy()
        let shown = expectation(description: "cached windows are presented")
        overlay.onShow = { shown.fulfill() }
        let failed = expectation(description: "activation failure is shown")
        overlay.onShowActivationFailure = { failed.fulfill() }
        let activator = WindowActivatorStub()
        activator.remainingFailures = 1
        let suiteName = "com.dreace.tabflow.tests.SwitcherCoordinator.RemoveFailedWindow"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: UserDefaultsSettingsStore(defaults: defaults))
        let coordinator = SwitcherCoordinator(
            windows: provider,
            activator: activator,
            thumbnails: ThumbnailProviderStub(),
            overlay: overlay,
            settings: settings
        )

        coordinator.begin(direction: .forward)
        await fulfillment(of: [shown], timeout: 1)
        overlay.onShow = nil
        coordinator.commit()
        await fulfillment(of: [failed], timeout: 1)

        coordinator.removeFailedWindow()

        XCTAssertTrue(coordinator.isVisible)
        XCTAssertEqual(coordinator.session?.windows.map(\.id), [current.id])
        XCTAssertEqual(overlay.presentedSessions.last?.windows.map(\.id), [current.id])
    }

    func testCancelDuringColdCacheOpenDoesNotActivateAfterRefresh() async {
        let current = window(1, title: "Current", isCurrent: true)
        let previous = window(2, title: "Previous", isCurrent: false)
        let provider = WindowProviderStub(cached: [], refreshed: [current, previous])
        let overlay = OverlaySpy()
        let suiteName = "com.dreace.tabflow.tests.SwitcherCoordinator.CancelDuringOpen"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: UserDefaultsSettingsStore(defaults: defaults))
        let activator = WindowActivatorStub()
        let coordinator = SwitcherCoordinator(
            windows: provider,
            activator: activator,
            thumbnails: ThumbnailProviderStub(),
            overlay: overlay,
            settings: settings
        )

        coordinator.begin(direction: .forward)
        coordinator.cancel()
        await provider.completeRefresh()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(overlay.showLoadingCount, 0)
        XCTAssertTrue(activator.activatedIDs.isEmpty)
        XCTAssertFalse(coordinator.isVisible)
    }

    func testCommitDuringColdCacheOpenHidesEmptyState() async {
        let provider = WindowProviderStub(cached: [], refreshed: [])
        let overlay = OverlaySpy()
        let suiteName = "com.dreace.tabflow.tests.SwitcherCoordinator.PendingCommitEmpty"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: UserDefaultsSettingsStore(defaults: defaults))
        let coordinator = SwitcherCoordinator(
            windows: provider,
            activator: WindowActivatorStub(),
            thumbnails: ThumbnailProviderStub(),
            overlay: overlay,
            settings: settings
        )

        coordinator.begin(direction: .forward)
        coordinator.commit()
        await provider.completeRefresh()
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(overlay.showLoadingCount, 0)
        XCTAssertFalse(coordinator.isVisible)
    }

    func testOpeningRefreshKeepsVisibleOrderAndDropsNewWindows() async {
        let firstCachedWindow = window(1, title: "First cached", isCurrent: true)
        let secondCachedWindow = window(2, title: "Second cached", isCurrent: false)
        let refreshedFirstWindow = window(1, title: "First refreshed", isCurrent: true)
        let refreshedSecondWindow = window(2, title: "Second refreshed", isCurrent: false)
        let newWindow = window(3, title: "New", isCurrent: false)
        let provider = WindowProviderStub(
            cached: [firstCachedWindow, secondCachedWindow],
            refreshed: [refreshedSecondWindow, refreshedFirstWindow, newWindow]
        )
        let overlay = OverlaySpy()
        let firstPresentation = expectation(description: "cached windows are presented")
        let refreshUpdate = expectation(description: "refreshed windows keep visible order")
        overlay.onShow = { firstPresentation.fulfill() }
        let suiteName = "com.dreace.tabflow.tests.SwitcherCoordinator.UsageOrder"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: UserDefaultsSettingsStore(defaults: defaults))
        settings.selectsPreviousWindow = false
        let coordinator = SwitcherCoordinator(
            windows: provider,
            activator: WindowActivatorStub(),
            thumbnails: ThumbnailProviderStub(),
            overlay: overlay,
            settings: settings
        )

        coordinator.begin(direction: .forward)
        await fulfillment(of: [firstPresentation], timeout: 1)
        overlay.onUpdate = { refreshUpdate.fulfill() }

        await provider.completeRefresh()
        await fulfillment(of: [refreshUpdate], timeout: 1)

        let updatedWindows = overlay.updatedSessions.last?.windows
        XCTAssertEqual(updatedWindows?.map(\.id), [
            refreshedFirstWindow.id,
            refreshedSecondWindow.id
        ])
        XCTAssertEqual(updatedWindows?.map(\.title), [
            "First refreshed",
            "Second refreshed"
        ])
        XCTAssertFalse(updatedWindows?.contains { $0.id == newWindow.id } == true)
        XCTAssertEqual(overlay.updatedSessions.last?.selectedIndex, 0)
    }

    func testOpeningRefreshDoesNotChangeSelectionToLaterUsageOrder() async {
        let finder = window(1, title: "Finder", isCurrent: true)
        let safari = window(2, title: "Safari", isCurrent: false)
        let xcode = window(3, title: "Xcode", isCurrent: false)
        let refreshedXcode = window(3, title: "Xcode", isCurrent: true)
        let refreshedFinder = window(1, title: "Finder", isCurrent: false)
        let refreshedSafari = window(2, title: "Safari", isCurrent: false)
        let provider = WindowProviderStub(
            cached: [finder, safari, xcode],
            refreshed: [refreshedXcode, refreshedFinder, refreshedSafari]
        )
        let overlay = OverlaySpy()
        let firstPresentation = expectation(description: "cached windows are presented")
        let refreshUpdate = expectation(description: "visible order stays frozen")
        overlay.onShow = { firstPresentation.fulfill() }
        let suiteName = "com.dreace.tabflow.tests.SwitcherCoordinator.PreviousWindow"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: UserDefaultsSettingsStore(defaults: defaults))
        XCTAssertTrue(settings.selectsPreviousWindow)
        let coordinator = SwitcherCoordinator(
            windows: provider,
            activator: WindowActivatorStub(),
            thumbnails: ThumbnailProviderStub(),
            overlay: overlay,
            settings: settings
        )

        coordinator.begin(direction: .forward)
        await fulfillment(of: [firstPresentation], timeout: 1)
        XCTAssertEqual(overlay.presentedSessions.last?.windows.map(\.title), ["Finder", "Safari", "Xcode"])
        XCTAssertEqual(overlay.presentedSessions.last?.selectedWindow?.title, "Safari")
        overlay.onUpdate = { refreshUpdate.fulfill() }

        await provider.completeRefresh()
        await fulfillment(of: [refreshUpdate], timeout: 1)

        let updated = overlay.updatedSessions.last
        XCTAssertEqual(updated?.windows.map(\.title), ["Finder", "Safari", "Xcode"])
        XCTAssertEqual(updated?.selectedWindow?.title, "Safari")
        XCTAssertEqual(updated?.selectedIndex, 1)
    }

    func testSwitcherInitialSelectionPicksPreviousWindowWhenCurrentIsFront() {
        let current = window(1, title: "Current", isCurrent: true)
        let previous = window(2, title: "Previous", isCurrent: false)
        let older = window(3, title: "Older", isCurrent: false)

        XCTAssertEqual(
            SwitcherInitialSelection.index(
                in: [current, previous, older],
                direction: .forward,
                selectsPreviousWindow: true
            ),
            1
        )
        XCTAssertEqual(
            SwitcherInitialSelection.index(
                in: [current, previous, older],
                direction: .forward,
                selectsPreviousWindow: false
            ),
            0
        )
    }

    func testSwitcherInitialSelectionUsesLiveFrontWindowInsteadOfStaleCurrentFlag() {
        let staleCurrent = window(1, title: "Previous", isCurrent: true)
        let liveCurrent = window(2, title: "Current", isCurrent: false)
        let older = window(3, title: "Older", isCurrent: false)

        XCTAssertEqual(
            SwitcherInitialSelection.index(
                in: [staleCurrent, liveCurrent, older],
                direction: .forward,
                selectsPreviousWindow: true,
                liveCurrentCGWindowID: liveCurrent.cgWindowID
            ),
            0
        )
        XCTAssertEqual(
            SwitcherInitialSelection.index(
                in: [staleCurrent, liveCurrent, older],
                direction: .forward,
                selectsPreviousWindow: true,
                liveCurrentCGWindowID: staleCurrent.cgWindowID
            ),
            1
        )
    }

    func testSwitcherInitialSelectionAssumesFirstWindowIsCurrentWhenUnmarked() {
        let first = window(1, title: "Current", isCurrent: false)
        let second = window(2, title: "Previous", isCurrent: false)

        XCTAssertEqual(
            SwitcherInitialSelection.index(
                in: [first, second],
                direction: .forward,
                selectsPreviousWindow: true
            ),
            1
        )
    }

    func testSwitcherInitialSelectionSelectsFirstCandidateWhenCurrentWindowIsExcluded() {
        let previous = window(2, title: "Previous", isCurrent: false)
        let older = window(3, title: "Older", isCurrent: false)

        XCTAssertEqual(
            SwitcherInitialSelection.index(
                in: [previous, older],
                direction: .forward,
                selectsPreviousWindow: true,
                liveCurrentCGWindowID: 1
            ),
            0
        )
    }

    func testScreenshotModeLoadsEveryThumbnailBeforeOpeningTaskFinishes() async {
        let firstWindow = window(1, title: "First", isCurrent: true)
        let secondWindow = window(2, title: "Second", isCurrent: false)
        let provider = WindowProviderStub(
            cached: [firstWindow, secondWindow],
            refreshed: [firstWindow, secondWindow]
        )
        let overlay = OverlaySpy()
        let shown = expectation(description: "overlay is shown")
        overlay.onShow = { shown.fulfill() }
        let suiteName = "com.dreace.tabflow.tests.SwitcherCoordinator.Thumbnails"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: UserDefaultsSettingsStore(defaults: defaults))
        settings.selectsPreviousWindow = false
        settings.showsThumbnails = true
        guard let image = Self.makeTestImage() else {
            XCTFail("Unable to create test thumbnail")
            return
        }
        let coordinator = SwitcherCoordinator(
            windows: provider,
            activator: WindowActivatorStub(),
            thumbnails: ThumbnailProviderStub(image: image),
            overlay: overlay,
            settings: settings,
            waitsForThumbnails: true
        )

        coordinator.begin(direction: .forward)
        await fulfillment(of: [shown], timeout: 1)
        await provider.completeRefresh()
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(
            Set(overlay.updatedThumbnailIDs),
            [firstWindow.id, secondWindow.id]
        )
    }

    func testLoadsThumbnailsForEveryVisibleWindow() async {
        let windows = (1...9).map { index in
            window(UInt64(index), title: "Window \(index)", isCurrent: index == 1)
        }
        let provider = WindowProviderStub(cached: windows, refreshed: windows)
        let overlay = OverlaySpy()
        let shown = expectation(description: "overlay is shown")
        overlay.onShow = { shown.fulfill() }
        let suiteName = "com.dreace.tabflow.tests.SwitcherCoordinator.AllThumbnails"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: UserDefaultsSettingsStore(defaults: defaults))
        settings.selectsPreviousWindow = false
        settings.showsThumbnails = true
        guard let image = Self.makeTestImage() else {
            XCTFail("Unable to create test thumbnail")
            return
        }
        let coordinator = SwitcherCoordinator(
            windows: provider,
            activator: WindowActivatorStub(),
            thumbnails: ThumbnailProviderStub(image: image),
            overlay: overlay,
            settings: settings
        )

        coordinator.begin(direction: .forward)
        await fulfillment(of: [shown], timeout: 1)
        await provider.completeRefresh()
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(Set(overlay.updatedThumbnailIDs), Set(windows.map(\.id)))
    }

    func testCachedThumbnailsAreShownThenUpdated() async {
        let firstWindow = window(1, title: "First", isCurrent: true)
        let provider = WindowProviderStub(cached: [firstWindow], refreshed: [firstWindow])
        let overlay = OverlaySpy()
        let shown = expectation(description: "overlay is shown")
        overlay.onShow = { shown.fulfill() }
        let ready = expectation(description: "thumbnail load finished")
        let suiteName = "com.dreace.tabflow.tests.SwitcherCoordinator.ThumbnailCache"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: UserDefaultsSettingsStore(defaults: defaults))
        settings.selectsPreviousWindow = false
        settings.showsThumbnails = true
        guard let cached = Self.makeTestImage(width: 2, height: 2),
              let refreshed = Self.makeTestImage(width: 4, height: 4) else {
            XCTFail("Unable to create test thumbnails")
            return
        }
        let thumbnails = ThumbnailProviderStub(cached: cached, refreshed: refreshed)
        let coordinator = SwitcherCoordinator(
            windows: provider,
            activator: WindowActivatorStub(),
            thumbnails: thumbnails,
            overlay: overlay,
            settings: settings,
            waitsForThumbnails: true
        )
        coordinator.onReadyForScreenshot = { ready.fulfill() }

        coordinator.begin(direction: .forward)
        await fulfillment(of: [shown], timeout: 1)
        await provider.completeRefresh()
        await fulfillment(of: [ready], timeout: 1)
        XCTAssertEqual(overlay.thumbnailWidths.first, cached.width)
        XCTAssertEqual(thumbnails.refreshCount, 1)
        XCTAssertEqual(overlay.latestThumbnails[firstWindow.id]?.width, refreshed.width)
        XCTAssertEqual(overlay.latestThumbnails[firstWindow.id]?.height, refreshed.height)
    }

    func testCancelDropsInFlightThumbnailUpdates() async {
        let firstWindow = window(1, title: "First", isCurrent: true)
        let provider = WindowProviderStub(cached: [firstWindow], refreshed: [firstWindow])
        let overlay = OverlaySpy()
        let shown = expectation(description: "overlay is shown")
        overlay.onShow = { shown.fulfill() }
        let refreshStarted = expectation(description: "thumbnail capture started")
        let suiteName = "com.dreace.tabflow.tests.SwitcherCoordinator.ThumbnailCancel"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: UserDefaultsSettingsStore(defaults: defaults))
        settings.selectsPreviousWindow = false
        settings.showsThumbnails = true
        guard let image = Self.makeTestImage() else {
            XCTFail("Unable to create test thumbnail")
            return
        }
        let thumbnails = ThumbnailProviderStub(cached: nil, refreshed: image)
        thumbnails.gatesRefresh = true
        thumbnails.onRefresh = { refreshStarted.fulfill() }
        let coordinator = SwitcherCoordinator(
            windows: provider,
            activator: WindowActivatorStub(),
            thumbnails: thumbnails,
            overlay: overlay,
            settings: settings
        )

        coordinator.begin(direction: .forward)
        await fulfillment(of: [shown], timeout: 1)
        await fulfillment(of: [refreshStarted], timeout: 1)
        coordinator.cancel()
        XCTAssertGreaterThanOrEqual(overlay.hideCount, 1)

        let staleUpdate = expectation(description: "cancelled capture must not update overlay")
        staleUpdate.isInverted = true
        overlay.onThumbnailUpdate = { staleUpdate.fulfill() }
        thumbnails.completeGatedRefresh()
        await fulfillment(of: [staleUpdate], timeout: 0.2)
        XCTAssertTrue(overlay.latestThumbnails.isEmpty)
    }

    func testReopenShowsCachedThumbnailThenRecaptures() async {
        let firstWindow = window(1, title: "First", isCurrent: true)
        let provider = WindowProviderStub(cached: [firstWindow], refreshed: [firstWindow])
        let overlay = OverlaySpy()
        let shown = expectation(description: "overlay is shown")
        overlay.onShow = { shown.fulfill() }
        let refreshStarted = expectation(description: "thumbnail capture started")
        let firstReady = expectation(description: "first thumbnail load finished")
        let suiteName = "com.dreace.tabflow.tests.SwitcherCoordinator.ThumbnailReopen"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: UserDefaultsSettingsStore(defaults: defaults))
        settings.selectsPreviousWindow = false
        settings.showsThumbnails = true
        guard let image = Self.makeTestImage() else {
            XCTFail("Unable to create test thumbnail")
            return
        }
        let thumbnails = ThumbnailProviderStub(cached: nil, refreshed: image)
        thumbnails.gatesRefresh = true
        thumbnails.onRefresh = { refreshStarted.fulfill() }
        let coordinator = SwitcherCoordinator(
            windows: provider,
            activator: WindowActivatorStub(),
            thumbnails: thumbnails,
            overlay: overlay,
            settings: settings,
            waitsForThumbnails: true
        )
        coordinator.onReadyForScreenshot = { firstReady.fulfill() }

        coordinator.begin(direction: .forward)
        await fulfillment(of: [shown], timeout: 1)
        await fulfillment(of: [refreshStarted], timeout: 1)
        thumbnails.onRefresh = nil
        await provider.completeRefresh()
        thumbnails.completeGatedRefresh()
        await fulfillment(of: [firstReady], timeout: 1)
        let capturedCount = thumbnails.refreshCount
        XCTAssertGreaterThanOrEqual(capturedCount, 1)

        coordinator.cancel()
        let shownAgain = expectation(description: "overlay is shown again")
        overlay.onShow = { shownAgain.fulfill() }
        let secondReady = expectation(description: "second thumbnail load finished")
        coordinator.onReadyForScreenshot = { secondReady.fulfill() }

        coordinator.begin(direction: .forward)
        await fulfillment(of: [shownAgain], timeout: 1)
        XCTAssertEqual(
            overlay.latestThumbnails[firstWindow.id]?.width,
            image.width,
            "Reopening the switcher should paint cached thumbnails before recapture starts"
        )
        await provider.completeRefresh()
        thumbnails.completeGatedRefresh()
        await fulfillment(of: [secondReady], timeout: 1)
        XCTAssertGreaterThan(thumbnails.refreshCount, capturedCount)
    }

    func testReopenKeepsLastDisplayedThumbnailsWhenServiceCacheIsStale() async {
        let firstWindow = window(1, title: "First", isCurrent: true)
        let provider = WindowProviderStub(cached: [firstWindow], refreshed: [firstWindow])
        let overlay = OverlaySpy()
        let shown = expectation(description: "overlay is shown")
        overlay.onShow = { shown.fulfill() }
        let refreshStarted = expectation(description: "thumbnail capture started")
        let firstReady = expectation(description: "first thumbnail load finished")
        let suiteName = "com.dreace.tabflow.tests.SwitcherCoordinator.StaleThumbnailCache"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: UserDefaultsSettingsStore(defaults: defaults))
        settings.selectsPreviousWindow = false
        settings.showsThumbnails = true
        guard let previous = Self.makeTestImage(width: 2, height: 2),
              let captured = Self.makeTestImage(width: 8, height: 8)
        else {
            XCTFail("Unable to create test thumbnails")
            return
        }
        let thumbnails = ThumbnailProviderStub(cached: previous, refreshed: captured)
        thumbnails.storesRefresh = false
        thumbnails.gatesRefresh = true
        thumbnails.onRefresh = { refreshStarted.fulfill() }
        let coordinator = SwitcherCoordinator(
            windows: provider,
            activator: WindowActivatorStub(),
            thumbnails: thumbnails,
            overlay: overlay,
            settings: settings,
            waitsForThumbnails: true
        )
        coordinator.onReadyForScreenshot = { firstReady.fulfill() }

        coordinator.begin(direction: .forward)
        await fulfillment(of: [shown], timeout: 1)
        await fulfillment(of: [refreshStarted], timeout: 1)
        thumbnails.onRefresh = nil
        await provider.completeRefresh()
        thumbnails.completeGatedRefresh()
        await fulfillment(of: [firstReady], timeout: 1)
        XCTAssertEqual(overlay.latestThumbnails[firstWindow.id]?.width, captured.width)

        coordinator.cancel()
        let shownAgain = expectation(description: "overlay is shown again")
        overlay.onShow = { shownAgain.fulfill() }

        coordinator.begin(direction: .forward)
        await fulfillment(of: [shownAgain], timeout: 1)
        XCTAssertEqual(
            overlay.latestThumbnails[firstWindow.id]?.width,
            captured.width,
            "Reopening should show the last displayed thumbnails, not the stale service cache"
        )
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(
            overlay.latestThumbnails[firstWindow.id]?.width,
            captured.width,
            "Stale service cache must not replace thumbnails already painted from the last session"
        )
    }

    func testScreenshotModeHidesWindowsOutsideTheFixtureAllowList() async {
        let finderWindow = window(1, title: "Project", bundle: "com.apple.finder", isCurrent: true)
        let terminalWindow = window(2, title: "capture", bundle: "com.apple.Terminal", isCurrent: false)
        let safariWindow = window(3, title: "Dashboard", bundle: "com.apple.Safari", isCurrent: false)
        let provider = WindowProviderStub(
            cached: [finderWindow, terminalWindow, safariWindow],
            refreshed: [finderWindow, terminalWindow, safariWindow]
        )
        let overlay = OverlaySpy()
        let shown = expectation(description: "overlay is shown")
        overlay.onShow = { shown.fulfill() }
        let suiteName = "com.dreace.tabflow.tests.SwitcherCoordinator.ScreenshotFilter"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(store: UserDefaultsSettingsStore(defaults: defaults))
        settings.selectsPreviousWindow = false
        let coordinator = SwitcherCoordinator(
            windows: provider,
            activator: WindowActivatorStub(),
            thumbnails: ThumbnailProviderStub(),
            overlay: overlay,
            settings: settings,
            allowedBundleIdentifiers: ScreenshotModeConfiguration.fixtureBundleIdentifiers
        )

        coordinator.begin(direction: .forward)
        await fulfillment(of: [shown], timeout: 1)
        XCTAssertEqual(
            overlay.presentedSessions.last?.windows.map(\.bundleIdentifier),
            ["com.apple.finder", "com.apple.Safari"]
        )
    }

    private func window(
        _ generation: UInt64,
        title: String,
        bundle: String = "com.example.application",
        isCurrent: Bool
    ) -> WindowRecord {
        WindowRecord(
            id: .init(pid: 100, generation: generation),
            pid: 100,
            bundleIdentifier: bundle,
            applicationName: "Application",
            applicationIconData: nil,
            title: title,
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            cgWindowID: CGWindowID(generation),
            isMinimized: false,
            isHidden: false,
            isFullScreen: false,
            isDialog: false,
            isOnScreen: true,
            displayName: "Display",
            isCurrent: isCurrent
        )
    }

    private static func makeTestImage(width: Int = 2, height: Int = 2) -> CGImage? {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        return context?.makeImage()
    }
}

@MainActor
private final class WindowProviderStub: WindowProviding {
    private let cached: [WindowRecord]
    private let refreshed: [WindowRecord]
    private var refreshContinuation: CheckedContinuation<[WindowRecord], Never>?
    private var pendingRefreshResult: [WindowRecord]?

    init(cached: [WindowRecord], refreshed: [WindowRecord]) {
        self.cached = cached
        self.refreshed = refreshed
    }

    func cachedWindows(options _: WindowQueryOptions) -> [WindowRecord] {
        cached
    }

    func refreshWindows(options _: WindowQueryOptions) async -> [WindowRecord] {
        if let pendingRefreshResult {
            self.pendingRefreshResult = nil
            return pendingRefreshResult
        }
        return await withCheckedContinuation { continuation in
            refreshContinuation = continuation
        }
    }

    func isWindowValid(_: WindowRecord.ID) -> Bool {
        true
    }

    func completeRefresh() {
        if let refreshContinuation {
            refreshContinuation.resume(returning: refreshed)
            self.refreshContinuation = nil
        } else {
            pendingRefreshResult = refreshed
        }
    }
}

@MainActor
private final class WindowActivatorStub: WindowActivating {
    var activatedIDs: [WindowRecord.ID] = []
    var remainingFailures = 0
    var onActivate: (() -> Void)?

    func activate(windowID: WindowRecord.ID, restoreMinimized _: Bool) async throws {
        activatedIDs.append(windowID)
        onActivate?()
        if remainingFailures > 0 {
            remainingFailures -= 1
            throw WindowActivationError.windowClosed(applicationName: "Application", title: "Window")
        }
    }
}

private final class ThumbnailProviderStub: ThumbnailProviding {
    private let cached: CGImage?
    private let refreshed: CGImage?
    private var stored: [CGWindowID: CGImage] = [:]
    private let lock = NSLock()
    private(set) var refreshCount = 0
    var gatesRefresh = false
    var storesRefresh = true
    var onRefresh: (() -> Void)?
    private var refreshContinuations: [CheckedContinuation<CGImage?, Never>] = []

    init(image: CGImage? = nil) {
        self.cached = image
        self.refreshed = image
    }

    init(cached: CGImage?, refreshed: CGImage?) {
        self.cached = cached
        self.refreshed = refreshed
    }

    func cachedThumbnail(for window: WindowRecord) async -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        if let windowID = window.cgWindowID, let stored = stored[windowID] {
            return stored
        }
        return cached
    }
    func refreshThumbnail(for window: WindowRecord, size _: CGSize) async -> CGImage? {
        lock.lock()
        refreshCount += 1
        lock.unlock()
        onRefresh?()
        if gatesRefresh {
            let image = await withCheckedContinuation { continuation in
                lock.lock()
                refreshContinuations.append(continuation)
                lock.unlock()
            }
            if storesRefresh, let windowID = window.cgWindowID, let image {
                lock.lock()
                stored[windowID] = image
                lock.unlock()
            }
            return image
        }
        if storesRefresh, let windowID = window.cgWindowID, let refreshed {
            lock.lock()
            stored[windowID] = refreshed
            lock.unlock()
        }
        return refreshed
    }
    func beginOverlayCaptureSession() async {}
    func completeGatedRefresh() {
        lock.lock()
        let pending = refreshContinuations
        refreshContinuations.removeAll()
        lock.unlock()
        pending.forEach { $0.resume(returning: refreshed) }
    }
    func discardThumbnails(forClosedWindowIDs _: Set<CGWindowID>) async {}
    func clearCache() async {}
    func finishCaptureSession() async {}
}

@MainActor
private final class OverlaySpy: OverlayPresenting {
    var presentedSessions: [SwitchSession] = []
    var updatedSessions: [SwitchSession] = []
    var updatedThumbnailIDs: [WindowRecord.ID] = []
    var latestThumbnails: [WindowRecord.ID: CGImage] = [:]
    private var imagesByCGWindowID: [CGWindowID: CGImage] = [:]
    var activationFailureMessages: [String] = []
    var thumbnailEpoch: UInt64 = 0
    var thumbnailWidths: [Int] = []
    var onShow: (() -> Void)?
    var onUpdate: (() -> Void)?
    var onShowLoading: (() -> Void)?
    var onShowNoWindows: (() -> Void)?
    var onShowActivationFailure: (() -> Void)?
    var onThumbnailUpdate: (() -> Void)?
    var showLoadingCount = 0
    var showNoWindowsCount = 0
    var hideCount = 0

    func show(session: SwitchSession, settings _: AppSettings) {
        presentedSessions.append(session)
        applyRememberedThumbnails(from: session)
        onShow?()
    }

    func update(session: SwitchSession, settings _: AppSettings) {
        updatedSessions.append(session)
        onUpdate?()
    }

    func showLoading(settings _: AppSettings) {
        showLoadingCount += 1
        onShowLoading?()
    }
    func beginThumbnailEpoch(_ epoch: UInt64) {
        thumbnailEpoch = epoch
    }
    func rememberThumbnails(_ images: [CGWindowID: CGImage]) {
        for (windowID, image) in images where imagesByCGWindowID[windowID] == nil {
            imagesByCGWindowID[windowID] = image
        }
    }
    func updateThumbnail(windowID: WindowRecord.ID, image: CGImage, epoch: UInt64, cgWindowID: CGWindowID?) {
        guard epoch == thumbnailEpoch else { return }
        if let cgWindowID {
            imagesByCGWindowID[cgWindowID] = image
        } else if let cgWindowID = presentedSessions.last?.windows.first(where: { $0.id == windowID })?.cgWindowID {
            imagesByCGWindowID[cgWindowID] = image
        }
        updatedThumbnailIDs.append(windowID)
        thumbnailWidths.append(image.width)
        latestThumbnails[windowID] = image
        onThumbnailUpdate?()
    }
    func seedThumbnailIfMissing(
        windowID: WindowRecord.ID,
        image: CGImage,
        epoch: UInt64,
        cgWindowID: CGWindowID?
    ) {
        guard latestThumbnails[windowID] == nil else { return }
        updateThumbnail(windowID: windowID, image: image, epoch: epoch, cgWindowID: cgWindowID)
    }
    func pruneThumbnails(keeping ids: Set<WindowRecord.ID>) {
        latestThumbnails = latestThumbnails.filter { ids.contains($0.key) }
    }
    func discardCachedThumbnails(forClosedWindowIDs _: Set<CGWindowID>) {}
    func showMessage(_: String) {}
    func showNoWindows() {
        showNoWindowsCount += 1
        onShowNoWindows?()
    }
    func showActivationFailure(_ message: String) {
        activationFailureMessages.append(message)
        onShowActivationFailure?()
    }
    func hide() {
        hideCount += 1
        latestThumbnails.removeAll()
    }

    private func applyRememberedThumbnails(from session: SwitchSession) {
        for window in session.windows {
            guard let cgWindowID = window.cgWindowID, let image = imagesByCGWindowID[cgWindowID] else {
                continue
            }
            latestThumbnails[window.id] = image
            thumbnailWidths.append(image.width)
        }
    }
}
