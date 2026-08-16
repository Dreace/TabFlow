import XCTest
@testable import TabFlow

final class SwitchSessionTests: XCTestCase {
    func testSelectionWrapsInBothDirections() {
        var session = SwitchSession(windows: [window(1), window(2), window(3)], selectedIndex: 0)

        session.move(.backward)
        XCTAssertEqual(session.selectedWindow?.id, window(3).id)

        session.move(.forward)
        XCTAssertEqual(session.selectedWindow?.id, window(1).id)
    }

    func testVerticalSelectionMovesByGridRowWithoutWrapping() {
        var session = SwitchSession(
            windows: (1...7).map { window(UInt64($0)) },
            selectedIndex: 1
        )

        session.moveVertically(.down, columns: 4)
        XCTAssertEqual(session.selectedIndex, 5)

        session.moveVertically(.up, columns: 4)
        XCTAssertEqual(session.selectedIndex, 1)

        session.moveVertically(.up, columns: 4)
        XCTAssertEqual(session.selectedIndex, 1)
    }

    func testSearchMatchesTitleApplicationAndBundleIdentifier() {
        let safari = window(1, title: "Pull Requests", application: "Safari", bundle: "com.apple.Safari")
        let terminal = window(2, title: "tabflow", application: "Terminal", bundle: "com.apple.Terminal")
        var session = SwitchSession(windows: [safari, terminal], selectedIndex: 0)

        session.updateQuery("terminal")
        XCTAssertEqual(session.filteredWindows.map(\.id), [terminal.id])

        session.updateQuery("com.apple.safari")
        XCTAssertEqual(session.filteredWindows.map(\.id), [safari.id])
    }

    func testRemovingSelectedWindowMigratesSelectionToNeighbor() {
        let first = window(1)
        let second = window(2)
        let third = window(3)
        var session = SwitchSession(windows: [first, second, third], selectedIndex: 1)

        session.removeSelectedWindow()

        XCTAssertEqual(session.windows.map(\.id), [first.id, third.id])
        XCTAssertEqual(session.selectedWindow?.id, third.id)
    }

    func testRemovingSelectedWindowDuringSearchKeepsFilteredNeighbor() {
        let first = window(1, title: "Alpha")
        let second = window(2, title: "Beta")
        let third = window(3, title: "Beta Two")
        var session = SwitchSession(windows: [first, second, third], selectedIndex: 0)
        session.updateQuery("Beta")
        XCTAssertEqual(session.selectedWindow?.id, second.id)

        session.removeSelectedWindow()

        XCTAssertEqual(session.windows.map(\.id), [first.id, third.id])
        XCTAssertEqual(session.filteredWindows.map(\.id), [third.id])
        XCTAssertEqual(session.selectedWindow?.id, third.id)
    }

    func testFrozenMergeKeepsVisibleOrderUpdatesRecordsAndDropsNewWindows() {
        let visibleCurrent = window(1, title: "Finder")
        let visiblePrevious = window(2, title: "Safari")
        let visibleOlder = window(3, title: "Xcode")
        let refreshedCurrent = window(1, title: "Finder Updated")
        let refreshedPrevious = window(2, title: "Safari")
        let refreshedOlder = window(3, title: "Xcode")
        let newWindow = window(4, title: "Notes")

        let merged = SwitcherListFreeze.merge(
            visible: [visibleCurrent, visiblePrevious, visibleOlder],
            refreshed: [refreshedOlder, newWindow, refreshedCurrent, refreshedPrevious]
        )

        XCTAssertEqual(merged.map(\.id), [
            visibleCurrent.id,
            visiblePrevious.id,
            visibleOlder.id
        ])
        XCTAssertEqual(merged.first?.title, "Finder Updated")
        XCTAssertFalse(merged.contains { $0.id == newWindow.id })
    }

    func testFrozenMergeReplacesTheListWhenNoVisibleWindowSurvives() {
        let cached = window(1, title: "Cached")
        let refreshed = window(2, title: "Refreshed")

        let merged = SwitcherListFreeze.merge(
            visible: [cached],
            refreshed: [refreshed]
        )

        XCTAssertEqual(merged.map(\.id), [refreshed.id])
    }

    func testFrozenMergeDropsClosedWindowsWithoutReorderingSurvivors() {
        let first = window(1)
        let second = window(2)
        let third = window(3)

        let merged = SwitcherListFreeze.merge(
            visible: [first, second, third],
            refreshed: [third, first]
        )

        XCTAssertEqual(merged.map(\.id), [first.id, third.id])
    }

    private func window(
        _ generation: UInt64,
        title: String = "Window",
        application: String = "Application",
        bundle: String? = "com.example.application"
    ) -> WindowRecord {
        WindowRecord(
            id: .init(pid: 100, generation: generation),
            pid: 100,
            bundleIdentifier: bundle,
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
}
