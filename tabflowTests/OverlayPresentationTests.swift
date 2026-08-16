import XCTest
@testable import TabFlow

final class OverlayPresentationTests: XCTestCase {
    func testAutomaticLayoutUsesASingleRowWhenWindowsFit() {
        XCTAssertEqual(
            OverlayLayoutResolver.resolve(
                .automatic,
                windowCount: 4,
                cardSize: .medium,
                screenWidth: 1_440
            ),
            .horizontal
        )
        XCTAssertEqual(
            OverlayLayoutResolver.resolve(
                .automatic,
                windowCount: 5,
                cardSize: .medium,
                screenWidth: 1_440
            ),
            .grid
        )
        XCTAssertEqual(
            OverlayLayoutResolver.resolve(
                .automatic,
                windowCount: 4,
                cardSize: .medium,
                screenWidth: 800
            ),
            .grid
        )
    }

    func testExplicitLayoutsAreNotRewritten() {
        XCTAssertEqual(
            OverlayLayoutResolver.resolve(.horizontal, windowCount: 9, cardSize: .medium, screenWidth: 1_440),
            .horizontal
        )
        XCTAssertEqual(
            OverlayLayoutResolver.resolve(.grid, windowCount: 2, cardSize: .medium, screenWidth: 1_440),
            .grid
        )
        XCTAssertEqual(
            OverlayLayoutResolver.resolve(.list, windowCount: 2, cardSize: .medium, screenWidth: 1_440),
            .list
        )
    }

    func testAppearancePreviewUsesASingleSampleCardLayout() {
        XCTAssertEqual(
            AppearancePreviewSample.resolvedLayout(overlayLayout: .list, cardSize: .medium),
            .list
        )
        XCTAssertEqual(
            AppearancePreviewSample.resolvedLayout(overlayLayout: .grid, cardSize: .small),
            .grid
        )
        XCTAssertEqual(
            AppearancePreviewSample.resolvedLayout(overlayLayout: .horizontal, cardSize: .large),
            .horizontal
        )
        XCTAssertEqual(
            AppearancePreviewSample.resolvedLayout(overlayLayout: .automatic, cardSize: .medium),
            .horizontal
        )
        XCTAssertEqual(AppearancePreviewSample.cardWidth(for: .small), 176)
        XCTAssertEqual(AppearancePreviewSample.cardWidth(for: .large), 240)
    }

    func testAppearancePreviewSampleWindowShowsMinimizedStatus() {
        let window = AppearancePreviewSample.window(
            applicationName: "TabFlow",
            applicationIconData: nil,
            title: "Sample Window"
        )
        XCTAssertEqual(window.title, "Sample Window")
        XCTAssertEqual(window.applicationName, "TabFlow")
        XCTAssertTrue(window.isMinimized)
        XCTAssertTrue(window.statusLabels.contains(String(localized: "window.status.minimized")))
        XCTAssertFalse(window.statusLabels.contains(String(localized: "window.status.previewUnavailable")))
    }

    func testAppearancePreviewThumbnailHasAFixedSize() {
        let image = AppearancePreviewSample.thumbnailImage()
        XCTAssertEqual(image?.width, AppearancePreviewSample.thumbnailWidth)
        XCTAssertEqual(image?.height, AppearancePreviewSample.thumbnailHeight)
    }

    func testAnimationPolicyHonorsPreferenceAndReduceMotion() {
        XCTAssertEqual(
            OverlayAnimationPolicy.motion(preference: .none, reduceMotion: false),
            OverlayAnimationPolicy.Motion(fadesPanel: false, fadeDuration: 0)
        )
        XCTAssertEqual(
            OverlayAnimationPolicy.motion(preference: .reduced, reduceMotion: false).fadeDuration,
            0.08
        )
        XCTAssertFalse(OverlayAnimationPolicy.motion(preference: .system, reduceMotion: true).fadesPanel)
        XCTAssertTrue(OverlayAnimationPolicy.motion(preference: .system, reduceMotion: false).fadesPanel)
    }

    func testEventTapSwallowsOnlyConsumedKeyUpsWhileSwitcherIsVisible() {
        XCTAssertFalse(
            SwitcherEventTapPolicy.swallowsKeyUp(
                isSwitcherVisible: false,
                keyCode: 48,
                shortcutKeyCode: 48
            )
        )
        XCTAssertTrue(
            SwitcherEventTapPolicy.swallowsKeyUp(
                isSwitcherVisible: true,
                keyCode: 48,
                shortcutKeyCode: 48
            )
        )
        XCTAssertTrue(
            SwitcherEventTapPolicy.swallowsKeyUp(
                isSwitcherVisible: true,
                keyCode: 53,
                shortcutKeyCode: 48
            )
        )
        XCTAssertFalse(
            SwitcherEventTapPolicy.swallowsKeyUp(
                isSwitcherVisible: true,
                keyCode: 0,
                shortcutKeyCode: 48
            )
        )
    }

    func testCurrentSpaceKeepsMinimizedWindowsWhenEnabled() {
        XCTAssertTrue(
            WindowSpaceInclusion.allows(
                isOnScreen: false,
                isMinimized: true,
                currentSpaceOnly: true,
                includesMinimizedWindows: true
            )
        )
        XCTAssertFalse(
            WindowSpaceInclusion.allows(
                isOnScreen: false,
                isMinimized: true,
                currentSpaceOnly: true,
                includesMinimizedWindows: false
            )
        )
        XCTAssertFalse(
            WindowSpaceInclusion.allows(
                isOnScreen: false,
                isMinimized: false,
                currentSpaceOnly: true,
                includesMinimizedWindows: true
            )
        )
        XCTAssertTrue(
            WindowSpaceInclusion.allows(
                isOnScreen: false,
                isMinimized: false,
                currentSpaceOnly: false,
                includesMinimizedWindows: false
            )
        )
        XCTAssertFalse(
            WindowSpaceInclusion.allows(
                isOnScreen: false,
                isMinimized: true,
                currentSpaceOnly: false,
                includesMinimizedWindows: false
            )
        )
        XCTAssertTrue(
            WindowSpaceInclusion.allows(
                isOnScreen: false,
                isMinimized: true,
                currentSpaceOnly: false,
                includesMinimizedWindows: true
            )
        )
    }

    func testPausedStatusBarUsesPauseSymbol() {
        XCTAssertEqual(StatusBarIconPolicy.systemSymbolName(isPaused: true), "pause.circle.fill")
        XCTAssertNil(StatusBarIconPolicy.systemSymbolName(isPaused: false))
    }

    func testDisplayNameIsHiddenOnASingleScreen() {
        XCTAssertFalse(OverlayDisplayNamePolicy.showsDisplayName(screenCount: 1))
        XCTAssertTrue(OverlayDisplayNamePolicy.showsDisplayName(screenCount: 2))
    }

    func testThumbnailLoadPlanPutsSelectedNeighborsFirstThenTheRest() {
        let windows = (1...9).map { generation in
            WindowRecord(
                id: .init(pid: 100, generation: UInt64(generation)),
                pid: 100,
                bundleIdentifier: "com.example.application",
                applicationName: "Application",
                applicationIconData: nil,
                title: "Window \(generation)",
                frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                cgWindowID: CGWindowID(generation),
                isMinimized: false,
                isHidden: false,
                isFullScreen: false,
                isDialog: false,
                isOnScreen: true,
                displayName: "Display",
                isCurrent: generation == 5
            )
        }
        let ordered = ThumbnailLoadPlan.windows(in: windows, selectedID: windows[4].id)
        XCTAssertEqual(
            ordered.prefix(5).map(\.id),
            [windows[4].id, windows[3].id, windows[5].id, windows[2].id, windows[6].id]
        )
        XCTAssertEqual(ordered.count, windows.count)
        XCTAssertEqual(Set(ordered.map(\.id)), Set(windows.map(\.id)))
    }

    func testLegacyRefreshIntervalsNormalizeToFiveSeconds() {
        XCTAssertEqual(WindowRefreshInterval.oneSecond.normalized, .fiveSeconds)
        XCTAssertEqual(WindowRefreshInterval.threeSeconds.normalized, .fiveSeconds)
        XCTAssertEqual(WindowRefreshInterval.fiveSeconds.normalized, .fiveSeconds)
        XCTAssertEqual(WindowRefreshInterval.oneSecond.duration, .seconds(5))
        XCTAssertEqual(WindowRefreshInterval.tenSeconds.duration, .seconds(10))
    }

    func testCachedWindowFilterAppliesUpdatedOptionsWithoutDroppingTheWholeList() async {
        await MainActor.run {
            let suiteName = "com.dreace.tabflow.tests.CachedWindowFilter"
            guard let defaults = UserDefaults(suiteName: suiteName) else {
                XCTFail("Unable to create isolated defaults suite")
                return
            }
            defaults.removePersistentDomain(forName: suiteName)
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let settings = AppSettings(store: UserDefaultsSettingsStore(defaults: defaults))
            settings.includesMinimizedWindows = false
            settings.ignoredBundleIdentifiers = ["com.example.ignored"]

            let visible = window(1, bundle: "com.example.visible")
            let minimized = window(2, bundle: "com.example.visible", isMinimized: true)
            let ignored = window(3, bundle: "com.example.ignored")
            let filtered = CachedWindowFilter.apply(
                [visible, minimized, ignored],
                options: WindowQueryOptions(settings: settings)
            )

            XCTAssertEqual(filtered.map(\.id), [visible.id])
        }
    }

    func testCachedWindowFilterReappliesSortOrderWithoutWaitingForRefresh() async {
        await MainActor.run {
            let suiteName = "com.dreace.tabflow.tests.CachedWindowFilter.Sort"
            guard let defaults = UserDefaults(suiteName: suiteName) else {
                XCTFail("Unable to create isolated defaults suite")
                return
            }
            defaults.removePersistentDomain(forName: suiteName)
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let settings = AppSettings(store: UserDefaultsSettingsStore(defaults: defaults))
            settings.sortOrder = .title
            let zebra = namedWindow(1, title: "Zebra", application: "B App")
            let alpha = namedWindow(2, title: "Alpha", application: "A App")
            let recentOrder = [zebra, alpha]
            let filtered = CachedWindowFilter.apply(
                recentOrder,
                options: WindowQueryOptions(settings: settings)
            )
            XCTAssertEqual(filtered.map(\.title), ["Alpha", "Zebra"])

            settings.sortOrder = .recent
            let recent = CachedWindowFilter.apply(
                recentOrder,
                options: WindowQueryOptions(settings: settings)
            )
            XCTAssertEqual(recent.map(\.title), ["Zebra", "Alpha"])
        }
    }

    func testDisplayCoordinateSpaceConvertsAppKitFramesUsingPrimaryTop() {
        let primary = CGRect(x: 0, y: 0, width: 1_440, height: 900)
        let above = CGRect(x: 0, y: 900, width: 1_440, height: 800)
        XCTAssertEqual(
            DisplayCoordinateSpace.cgFrame(fromAppKitFrame: primary, primaryTop: 900),
            CGRect(x: 0, y: 0, width: 1_440, height: 900)
        )
        XCTAssertEqual(
            DisplayCoordinateSpace.cgFrame(fromAppKitFrame: above, primaryTop: 900),
            CGRect(x: 0, y: -800, width: 1_440, height: 800)
        )
        XCTAssertEqual(
            DisplayCoordinateSpace.cgPoint(fromAppKitPoint: CGPoint(x: 720, y: 450), primaryTop: 900),
            CGPoint(x: 720, y: 450)
        )
        let windowFrame = CGRect(x: 100, y: -200, width: 200, height: 200)
        XCTAssertGreaterThan(
            DisplayCoordinateSpace.intersectionArea(
                DisplayCoordinateSpace.cgFrame(fromAppKitFrame: above, primaryTop: 900),
                windowFrame
            ),
            0
        )
        XCTAssertEqual(
            DisplayCoordinateSpace.intersectionArea(
                DisplayCoordinateSpace.cgFrame(fromAppKitFrame: primary, primaryTop: 900),
                windowFrame
            ),
            0
        )
    }

    func testThumbnailCacheRetentionRemovesOnlyClosedWindowIDs() {
        XCTAssertEqual(
            ThumbnailCacheRetention.closedWindowIDs(previous: [1, 2, 3], current: [2, 3, 4]),
            [1]
        )
        XCTAssertTrue(
            ThumbnailCacheRetention.closedWindowIDs(previous: [1, 2], current: [1, 2]).isEmpty
        )
        XCTAssertTrue(
            ThumbnailCacheRetention.closedWindowIDs(previous: [], current: [1]).isEmpty
        )
        XCTAssertEqual(
            ThumbnailCacheRetention.closedWindowIDs(previous: [1, 2], current: []),
            [1, 2]
        )
    }

    func testOverlayThumbnailCacheDropsImagesForWindowsNoLongerInSession() {
        guard let kept = makeTestImage(), let stale = makeTestImage() else {
            XCTFail("Unable to create test thumbnails")
            return
        }
        let retained = OverlayThumbnailCache.retained(
            [1: kept, 2: stale, 3: stale],
            keeping: [1]
        )
        XCTAssertEqual(Set(retained.keys), [1])
        XCTAssertTrue(
            OverlayThumbnailCache.retained([1: kept], keeping: []).isEmpty
        )
    }

    func testOverlayThumbnailCacheCapsCountWhilePreferringLiveWindowIDs() {
        guard let small = makeTestImage(), let other = makeTestImage() else {
            XCTFail("Unable to create test thumbnails")
            return
        }
        let capped = OverlayThumbnailCache.capped(
            [1: small, 2: other, 3: other],
            preferring: [2, 3],
            maximumCount: 2,
            maximumBytes: 24 * 1_024 * 1_024
        )
        XCTAssertEqual(capped.count, 2)
        XCTAssertNotNil(capped[2])
        XCTAssertNotNil(capped[3])
        XCTAssertNil(capped[1])
    }

    func testRememberedThumbnailsDoNotReplaceAlreadyPersistedImages() {
        guard let persisted = makeTestImage(width: 8, height: 8), let stale = makeTestImage(width: 2, height: 2) else {
            XCTFail("Unable to create test thumbnails")
            return
        }
        let merged = OverlayThumbnailCache.fillingGaps(
            existing: [1: persisted],
            remembered: [1: stale, 2: stale]
        )
        XCTAssertEqual(merged[1]?.width, persisted.width)
        XCTAssertEqual(merged[2]?.width, stale.width)
    }

    func testNewerThumbnailCaptureGenerationsReplaceOlderCachedEntries() {
        XCTAssertTrue(
            ThumbnailCapturePersistence.shouldReplaceCachedEntry(
                existingGeneration: 1,
                incomingGeneration: 1
            )
        )
        XCTAssertTrue(
            ThumbnailCapturePersistence.shouldReplaceCachedEntry(
                existingGeneration: 1,
                incomingGeneration: 2
            )
        )
        XCTAssertFalse(
            ThumbnailCapturePersistence.shouldReplaceCachedEntry(
                existingGeneration: 3,
                incomingGeneration: 2
            )
        )
    }

    func testThumbnailImageIndexRemapsCacheOntoWindowRecordIDs() {
        let first = namedWindow(1, title: "First", application: "Application")
        let second = namedWindow(2, title: "Second", application: "Application")
        guard let image = CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.makeImage() else {
            XCTFail("Unable to create test thumbnail")
            return
        }
        let overlay = ThumbnailImageIndex.overlayThumbnails(
            windows: [first, second],
            imagesByCGWindowID: [1: image]
        )
        XCTAssertEqual(overlay[first.id]?.width, image.width)
        XCTAssertNil(overlay[second.id])
    }

    func testThumbnailCaptureDeduperClaimsEachWindowOnce() {
        let first = namedWindow(1, title: "First", application: "Application")
        let second = namedWindow(2, title: "Second", application: "Application")
        var started: Set<CGWindowID> = []
        XCTAssertEqual(
            ThumbnailCaptureDeduper.claim([first, second], started: &started).map(\.id),
            [first.id, second.id]
        )
        XCTAssertEqual(started, [1, 2])
        XCTAssertTrue(ThumbnailCaptureDeduper.claim([first, second], started: &started).isEmpty)
    }

    private func makeTestImage(width: Int = 2, height: Int = 2) -> CGImage? {
        CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.makeImage()
    }

    private func namedWindow(
        _ generation: UInt64,
        title: String,
        application: String
    ) -> WindowRecord {
        WindowRecord(
            id: .init(pid: 100, generation: generation),
            pid: 100,
            bundleIdentifier: "com.example.application",
            applicationName: application,
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
            isCurrent: false
        )
    }

    private func window(
        _ generation: UInt64,
        bundle: String = "com.example.application",
        isMinimized: Bool = false
    ) -> WindowRecord {
        WindowRecord(
            id: .init(pid: 100, generation: generation),
            pid: 100,
            bundleIdentifier: bundle,
            applicationName: "Application",
            applicationIconData: nil,
            title: "Window",
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            cgWindowID: CGWindowID(generation),
            isMinimized: isMinimized,
            isHidden: false,
            isFullScreen: false,
            isDialog: false,
            isOnScreen: true,
            displayName: "Display",
            isCurrent: false
        )
    }
}
