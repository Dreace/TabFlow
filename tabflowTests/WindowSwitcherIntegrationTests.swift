import AppKit
import ApplicationServices
import CoreGraphics
import XCTest
@testable import TabFlow

@MainActor
final class WindowSwitcherIntegrationTests: XCTestCase {
    func testLiveWindowServerZOrderChangesAfterActivatingAnotherApp() async throws {
        let before = WindowServerList.onScreenLayer0WindowsFrontToBack()
        trace("live-before", WindowScanTrace.liveZOrderSummary(before))
        guard before.count >= 2 else {
            throw XCTSkip("Need at least two on-screen layer-0 windows")
        }

        let originalFrontPID = before.first?.pid
        let target = try skipUnlessActivatable(behind: before)
        target.activate(options: [])
        addTeardownBlock {
            originalFrontPID.flatMap { NSRunningApplication(processIdentifier: $0) }?.activate(options: [])
        }
        let changed = await waitUntilZOrderFrontChanges(from: before[0].id)
        let after = WindowServerList.onScreenLayer0WindowsFrontToBack()
        trace("live-after", WindowScanTrace.liveZOrderSummary(after))

        XCTAssertTrue(changed, "Window Server z-order did not change after activating \(target.localizedName ?? "app")")
        XCTAssertEqual(after.first?.pid, target.processIdentifier)
        XCTAssertEqual(after.dropFirst().first?.id, before.first?.id)
    }

    func testRepositoryOrderMatchesLiveZOrderAndHasUniqueWindowIDs() async throws {
        let settings = isolatedSettings()
        let options = WindowQueryOptions(settings: settings)
        let repository = AccessibilityWindowRepository(mruStore: MRUStore())

        let records = await repository.refreshWindows(options: options)
        let live = WindowServerList.onScreenLayer0WindowsFrontToBack()
        trace("live", WindowScanTrace.liveZOrderSummary(live))
        trace("repository", WindowScanTrace.summary(records: records))

        XCTAssertFalse(records.isEmpty, "Repository returned no windows. AX trusted=\(AXIsProcessTrusted())")
        XCTAssertTrue(
            WindowScanTrace.duplicateCGWindowIDs(in: records).isEmpty,
            "Duplicate CGWindowIDs: \(WindowScanTrace.summary(records: records))"
        )

        let liveIDs = live.map(\.id)
        let alignedLive = liveIDs.filter { id in records.contains { $0.cgWindowID == id } }
        let alignedRepo = WindowScanTrace.onScreenIDs(in: records, matching: liveIDs)
        XCTAssertEqual(Set(alignedRepo), Set(alignedLive), "Repository is missing on-screen windows")
        XCTAssertEqual(
            alignedRepo.first,
            alignedLive.first,
            "Repository front window is not the live current window.\nlive=\(alignedLive)\nrepo=\(alignedRepo)\n\(WindowScanTrace.summary(records: records))"
        )

        let currentIDs = records.filter(\.isCurrent).compactMap(\.cgWindowID)
        XCTAssertEqual(currentIDs, alignedLive.prefix(1).map { $0 }, "isCurrent is not the frontmost included window")
        XCTAssertEqual(
            SwitcherInitialSelection.index(
                in: records,
                direction: .forward,
                selectsPreviousWindow: true
            ),
            records.count > 1 ? 1 : 0,
            "Initial selection is not the previous window"
        )
    }

    func testRepositoryOrderTracksLiveZOrderAfterActivatingAnotherApp() async throws {
        let settings = isolatedSettings()
        let options = WindowQueryOptions(settings: settings)
        let repository = AccessibilityWindowRepository(mruStore: MRUStore())

        let beforeLive = WindowServerList.onScreenLayer0WindowsFrontToBack()
        let before = await repository.refreshWindows(options: options)
        trace("before-live", WindowScanTrace.liveZOrderSummary(beforeLive))
        trace("before-repo", WindowScanTrace.summary(records: before))
        guard beforeLive.count >= 2, before.count >= 2 else {
            throw XCTSkip("Need at least two windows to compare usage order")
        }

        let originalFrontPID = beforeLive.first?.pid
        let target = try skipUnlessActivatable(behind: beforeLive)
        target.activate(options: [])
        addTeardownBlock {
            originalFrontPID.flatMap { NSRunningApplication(processIdentifier: $0) }?.activate(options: [])
        }
        let changed = await waitUntilZOrderFrontChanges(from: beforeLive[0].id)
        XCTAssertTrue(changed, "Window Server z-order did not change after activating \(target.localizedName ?? "app")")

        let afterLive = WindowServerList.onScreenLayer0WindowsFrontToBack()
        let after = await repository.refreshWindows(options: options)
        trace("after-live", WindowScanTrace.liveZOrderSummary(afterLive))
        trace("after-repo", WindowScanTrace.summary(records: after))

        XCTAssertNotEqual(
            after.compactMap(\.cgWindowID).prefix(2).map { $0 },
            before.compactMap(\.cgWindowID).prefix(2).map { $0 },
            "Repository order did not change after a real window activation"
        )

        let liveIDs = afterLive.map(\.id)
        let alignedLive = liveIDs.filter { id in after.contains { $0.cgWindowID == id } }
        let alignedRepo = WindowScanTrace.onScreenIDs(in: after, matching: liveIDs)
        XCTAssertEqual(Set(alignedRepo), Set(alignedLive), "Repository is missing on-screen windows after activation")
        XCTAssertEqual(
            alignedRepo.first,
            alignedLive.first,
            "Repository order after activation does not put the live current window first"
        )
        XCTAssertEqual(after.first?.cgWindowID, afterLive.first?.id)
        XCTAssertEqual(after.first?.isCurrent, true)
        XCTAssertEqual(
            after[SwitcherInitialSelection.index(
                in: after,
                direction: .forward,
                selectsPreviousWindow: true
            )].cgWindowID,
            beforeLive.first?.id,
            "Selected window is not the previously focused window"
        )
    }

    func testOpeningSwitcherUsesRepositoryRefreshOrderAndSelectsPreviousWindow() async throws {
        let settings = isolatedSettings()
        let options = WindowQueryOptions(settings: settings)
        let repository = AccessibilityWindowRepository(mruStore: MRUStore())
        _ = await repository.refreshWindows(options: options)

        let beforeLive = WindowServerList.onScreenLayer0WindowsFrontToBack()
        guard beforeLive.count >= 2 else {
            throw XCTSkip("Need at least two on-screen windows")
        }
        let originalFrontPID = beforeLive.first?.pid
        let target = try skipUnlessActivatable(behind: beforeLive)
        target.activate(options: [])
        addTeardownBlock {
            originalFrontPID.flatMap { NSRunningApplication(processIdentifier: $0) }?.activate(options: [])
        }
        _ = await waitUntilZOrderFrontChanges(from: beforeLive[0].id)
        let sortedAfterSwitch = await repository.refreshWindows(options: options)
        trace("after-switch-scan", WindowScanTrace.summary(records: sortedAfterSwitch))

        let provider = SignalingWindowProvider(repository: repository)
        let overlay = OverlaySpy()
        let refreshCompleted = expectation(description: "live repository refresh finished")
        provider.onRefresh = { records in
            self.trace("coordinator-refresh-source", WindowScanTrace.summary(records: records))
            refreshCompleted.fulfill()
        }
        let coordinator = SwitcherCoordinator(
            windows: provider,
            activator: provider,
            thumbnails: ThumbnailProviderStub(),
            overlay: overlay,
            settings: settings
        )

        coordinator.begin(direction: .forward)
        await fulfillment(of: [refreshCompleted], timeout: 30)

        let session = overlay.updatedSessions.last ?? overlay.presentedSessions.last
        let live = WindowServerList.onScreenLayer0WindowsFrontToBack()
        trace("live-at-open", WindowScanTrace.liveZOrderSummary(live))
        trace("session", session.map(WindowScanTrace.sessionSummary) ?? "nil")

        let records = try XCTUnwrap(session?.windows)
        XCTAssertGreaterThanOrEqual(records.count, 2)
        XCTAssertEqual(
            overlay.presentedSessions.last?.windows.map(\.id),
            sortedAfterSwitch.map(\.id),
            "Switcher should open with the order produced by the post-switch scan"
        )
        if let updatedIDs = overlay.updatedSessions.last?.windows.map(\.id),
           let presentedIDs = overlay.presentedSessions.last?.windows.map(\.id) {
            XCTAssertEqual(
                Array(updatedIDs.prefix(presentedIDs.count)),
                presentedIDs,
                "Opening refresh must not reorder the visible switcher list"
            )
        }
        XCTAssertEqual(session?.selectedIndex, 1)
        XCTAssertEqual(session?.selectedWindow?.cgWindowID, beforeLive.first?.id)
        XCTAssertEqual(session?.windows.first?.isCurrent, true)
        XCTAssertNotEqual(session?.selectedWindow?.cgWindowID, session?.windows.first?.cgWindowID)
    }

    func testActivatingAnotherWindowOfTheSameAppRaisesTheTarget() async throws {
        let settings = isolatedSettings()
        let options = WindowQueryOptions(settings: settings)
        let repository = AccessibilityWindowRepository(mruStore: MRUStore())
        let records = await repository.refreshWindows(options: options)
        let siblings = Dictionary(
            grouping: records.filter { record in
                record.cgWindowID != nil && record.isOnScreen && !record.isMinimized
            },
            by: \.pid
        ).values.first { $0.count >= 2 }
        guard let siblings else {
            throw XCTSkip("Need two on-screen windows from the same application")
        }

        let current = siblings.first(where: \.isCurrent) ?? siblings[0]
        let target = try XCTUnwrap(siblings.first { $0.id != current.id })
        let targetID = try XCTUnwrap(target.cgWindowID)
        let originalFrontID = WindowServerList.onScreenLayer0IDsFrontToBack().first
        addTeardownBlock {
            originalFrontID.flatMap { id in
                WindowServerList.onScreenLayer0WindowsFrontToBack().first { $0.id == id }
            }.flatMap { NSRunningApplication(processIdentifier: $0.pid) }?.activate(options: [])
        }

        try await repository.activate(windowID: target.id, restoreMinimized: true)
        let raised = await waitUntilProcessFrontWindow(pid: target.pid, equals: targetID)
        XCTAssertTrue(
            raised,
            "Same-app window did not come to front. target=\(target.title) pid=\(target.pid) cg=\(targetID) front=\(String(describing: WindowServerList.frontmostLayer0WindowID(for: target.pid))) trusted=\(AXIsProcessTrusted())"
        )
    }

    private func skipUnlessActivatable(
        behind windows: [WindowServerList.OnScreenWindow]
    ) throws -> NSRunningApplication {
        guard let application = activatableApplication(behind: windows) else {
            throw XCTSkip("No other regular application behind the front window")
        }
        return application
    }

    private func isolatedSettings() -> AppSettings {
        let suiteName = "com.dreace.tabflow.tests.integration.\(name)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let settings = AppSettings(store: UserDefaultsSettingsStore(defaults: defaults))
        settings.sortOrder = .recent
        settings.selectsPreviousWindow = true
        settings.groupsApplications = false
        settings.includesCurrentWindow = true
        settings.showsThumbnails = false
        return settings
    }

    private func activatableApplication(
        behind windows: [WindowServerList.OnScreenWindow]
    ) -> NSRunningApplication? {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        return windows.dropFirst().compactMap { window in
            guard window.pid != selfPID,
                  let application = NSRunningApplication(processIdentifier: window.pid),
                  application.activationPolicy == .regular,
                  !application.isTerminated
            else { return nil }
            return application
        }.first
    }

    private func waitUntilZOrderFrontChanges(from previousFrontID: CGWindowID) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if WindowServerList.onScreenLayer0IDsFrontToBack().first != previousFrontID {
                return true
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    private func waitUntilProcessFrontWindow(pid: pid_t, equals windowID: CGWindowID) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if WindowServerList.frontmostLayer0WindowID(for: pid) == windowID {
                return true
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    private func trace(_ label: String, _ message: String) {
        print("TABFLOW_TRACE \(label): \(message)")
    }
}

@MainActor
private final class SignalingWindowProvider: WindowProviding, WindowActivating {
    private let repository: AccessibilityWindowRepository
    var onRefresh: (([WindowRecord]) -> Void)?

    init(repository: AccessibilityWindowRepository) {
        self.repository = repository
    }

    func cachedWindows(options: WindowQueryOptions) async -> [WindowRecord] {
        await repository.cachedWindows(options: options)
    }

    func refreshWindows(options: WindowQueryOptions) async -> [WindowRecord] {
        let records = await repository.refreshWindows(options: options)
        onRefresh?(records)
        return records
    }

    func isWindowValid(_ windowID: WindowRecord.ID) async -> Bool {
        await repository.isWindowValid(windowID)
    }

    func activate(windowID: WindowRecord.ID, restoreMinimized: Bool) async throws {
        try await repository.activate(windowID: windowID, restoreMinimized: restoreMinimized)
    }
}

private final class ThumbnailProviderStub: ThumbnailProviding {
    func cachedThumbnail(for _: WindowRecord) async -> CGImage? { nil }
    func refreshThumbnail(for _: WindowRecord, size _: CGSize) async -> CGImage? { nil }
    func beginOverlayCaptureSession() async {}
    func discardThumbnails(forClosedWindowIDs _: Set<CGWindowID>) async {}
    func clearCache() async {}
    func finishCaptureSession() async {}
}

@MainActor
private final class OverlaySpy: OverlayPresenting {
    var presentedSessions: [SwitchSession] = []
    var updatedSessions: [SwitchSession] = []

    func show(session: SwitchSession, settings _: AppSettings) {
        presentedSessions.append(session)
    }

    func update(session: SwitchSession, settings _: AppSettings) {
        updatedSessions.append(session)
    }

    func showLoading(settings _: AppSettings) {}
    func beginThumbnailEpoch(_: UInt64) {}
    func updateThumbnail(windowID _: WindowRecord.ID, image _: CGImage, epoch _: UInt64, cgWindowID _: CGWindowID?) {}
    func pruneThumbnails(keeping _: Set<WindowRecord.ID>) {}
    func discardCachedThumbnails(forClosedWindowIDs _: Set<CGWindowID>) {}
    func showMessage(_: String) {}
    func showNoWindows() {}
    func showActivationFailure(_: String) {}
    func hide() {}
}
