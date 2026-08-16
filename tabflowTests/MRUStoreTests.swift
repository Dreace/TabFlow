import XCTest
@testable import TabFlow

final class MRUStoreTests: XCTestCase {
    func testRecentlyFocusedWindowMovesToFrontAndMissingIDsAreDiscarded() async {
        let store = MRUStore()
        let first = window(1, cgWindowID: 11)
        let second = window(2, cgWindowID: 22)

        await store.recordFocus(second)
        var ordered = await store.order([first, second])
        XCTAssertEqual(ordered.map(\.id), [second.id, first.id])

        await store.discardMissing(from: [first])
        ordered = await store.order([first])
        XCTAssertEqual(ordered.map(\.id), [first.id])
    }

    func testUnknownWindowsKeepIncomingOrderAfterKnownMRUEntries() async {
        let store = MRUStore()
        let recent = window(1, cgWindowID: 11)
        let older = window(2, cgWindowID: 22)
        let unknown = window(3, cgWindowID: 33)
        await store.recordFocus(recent)

        let ordered = await store.order([unknown, older, recent])
        XCTAssertEqual(ordered.map(\.id), [recent.id, unknown.id, older.id])
    }

    func testFocusHistoryFollowsCGWindowIDWhenRecordIDChanges() async {
        let store = MRUStore()
        let focused = window(1, cgWindowID: 50)
        let sameWindowNewID = window(99, cgWindowID: 50)
        let other = window(2, cgWindowID: 51)
        await store.recordFocus(focused)

        let ordered = await store.order([other, sameWindowNewID])
        XCTAssertEqual(ordered.map(\.cgWindowID), [50, 51])
    }

    func testStoredFocusHistoryOutranksZOrder() async {
        let store = MRUStore()
        let previouslyFront = window(1, cgWindowID: 50)
        let nowFront = window(2, cgWindowID: 51)
        let older = window(3, cgWindowID: 52)
        await store.recordFocus(previouslyFront)

        let ordered = await store.order(
            [previouslyFront, nowFront, older],
            frontToBackCGWindowIDs: [51, 50, 52]
        )
        XCTAssertEqual(ordered.map(\.cgWindowID), [50, 51, 52])
    }

    private func window(_ generation: UInt64, cgWindowID: CGWindowID?) -> WindowRecord {
        WindowRecord(
            id: .init(pid: 100, generation: generation),
            pid: 100,
            bundleIdentifier: "com.example.application",
            applicationName: "Application",
            applicationIconData: nil,
            title: "Window \(generation)",
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            cgWindowID: cgWindowID,
            isMinimized: false,
            isHidden: false,
            isFullScreen: false,
            isDialog: false,
            isOnScreen: true,
            displayName: nil,
            isCurrent: false
        )
    }
}
