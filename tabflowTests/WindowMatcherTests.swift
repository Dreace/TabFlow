import ApplicationServices
import XCTest
@testable import TabFlow

final class WindowMatcherTests: XCTestCase {
    func testExactPIDTitleAndGeometryWins() {
        let frame = CGRect(x: 40, y: 80, width: 900, height: 700)
        let exact = WindowMatchingCandidate(id: 1, pid: 10, title: "Document", frame: frame, layer: 0)
        let nearby = WindowMatchingCandidate(
            id: 2,
            pid: 10,
            title: "Other",
            frame: frame.offsetBy(dx: 5, dy: 5),
            layer: 0
        )

        let result = WindowMatcher.bestMatch(
            pid: 10,
            title: "Document",
            frame: frame,
            candidates: [nearby, exact]
        )

        XCTAssertEqual(result, exact)
    }

    func testDifferentProcessAndNonWindowLayerAreRejected() {
        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let differentPID = WindowMatchingCandidate(id: 1, pid: 11, title: "Document", frame: frame, layer: 0)
        let overlay = WindowMatchingCandidate(id: 2, pid: 10, title: "Document", frame: frame, layer: 12)

        let result = WindowMatcher.bestMatch(
            pid: 10,
            title: "Document",
            frame: frame,
            candidates: [differentPID, overlay]
        )

        XCTAssertNil(result)
    }

    func testSameProcessLayerZeroWindowDoesNotMatchWithoutTitleOrGeometry() {
        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let candidate = WindowMatchingCandidate(
            id: 4,
            pid: 10,
            title: "Untitled",
            frame: CGRect(x: 200, y: 200, width: 400, height: 300),
            layer: 0
        )

        let result = WindowMatcher.bestMatch(
            pid: 10,
            title: "Document",
            frame: frame,
            candidates: [candidate]
        )

        XCTAssertNil(result)
    }

    func testBestMatchDoesNotReuseClaimedWindowIDs() {
        let leftFrame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let rightFrame = leftFrame.offsetBy(dx: 40, dy: 0)
        let first = WindowMatchingCandidate(id: 1, pid: 10, title: "Left", frame: leftFrame, layer: 0)
        let second = WindowMatchingCandidate(id: 2, pid: 10, title: "Right", frame: rightFrame, layer: 0)

        let firstMatch = WindowMatcher.bestMatch(
            pid: 10,
            title: "Left",
            frame: leftFrame,
            candidates: [first, second]
        )
        let secondMatch = WindowMatcher.bestMatch(
            pid: 10,
            title: "Right",
            frame: rightFrame,
            candidates: [first, second],
            excluding: Set([firstMatch?.id].compactMap { $0 })
        )

        XCTAssertEqual(firstMatch?.id, 1)
        XCTAssertEqual(secondMatch?.id, 2)
        XCTAssertNotEqual(firstMatch?.id, secondMatch?.id)
    }

    func testPrefixedTitlesDistinguishSameGeometrySiblingWindows() {
        let frame = CGRect(x: 0, y: 25, width: 1440, height: 900)
        let first = WindowMatchingCandidate(
            id: 11,
            pid: 10,
            title: "App.swift — tabflow — Visual Studio Code",
            frame: frame,
            layer: 0
        )
        let second = WindowMatchingCandidate(
            id: 22,
            pid: 10,
            title: "WindowMatcher.swift — tabflow — Visual Studio Code",
            frame: frame,
            layer: 0
        )

        let firstMatch = WindowMatcher.bestMatch(
            pid: 10,
            title: "WindowMatcher.swift — tabflow",
            frame: frame,
            candidates: [first, second]
        )
        let secondMatch = WindowMatcher.bestMatch(
            pid: 10,
            title: "App.swift — tabflow",
            frame: frame,
            candidates: [first, second],
            excluding: Set([firstMatch?.id].compactMap { $0 })
        )

        XCTAssertEqual(firstMatch?.id, 22)
        XCTAssertEqual(secondMatch?.id, 11)
    }

    func testAmbiguousSameGeometryWindowsDoNotGuessAWindowID() {
        let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let first = WindowMatchingCandidate(id: 11, pid: 10, title: "", frame: frame, layer: 0)
        let second = WindowMatchingCandidate(id: 22, pid: 10, title: "", frame: frame, layer: 0)

        let result = WindowMatcher.bestMatch(
            pid: 10,
            title: "App.swift — tabflow",
            frame: frame,
            candidates: [first, second]
        )

        XCTAssertNil(result)
    }

    func testPreferredWindowIDWinsOverTitleAndGeometry() {
        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let tempting = WindowMatchingCandidate(
            id: 11,
            pid: 10,
            title: "Document",
            frame: frame,
            layer: 0
        )
        let preferred = WindowMatchingCandidate(
            id: 22,
            pid: 10,
            title: "Other",
            frame: frame.offsetBy(dx: 400, dy: 0),
            layer: 0
        )

        let result = WindowMatcher.bestMatch(
            pid: 10,
            title: "Document",
            frame: frame,
            candidates: [tempting, preferred],
            preferredWindowID: 22
        )

        XCTAssertEqual(result?.id, 22)
    }

    func testWindowProcessEnumeratorUnionsWorkspaceAndWindowPIDs() {
        let pids = WindowProcessEnumerator.pidsToInspect(
            workspacePIDs: [10, 11],
            windowPIDs: [11, 12, 13],
            excluding: 13
        )

        XCTAssertEqual(pids, [10, 11, 12])
    }

    func testAXElementComparisonTreatsNilAsNotEqual() {
        XCTAssertFalse(AXElementComparison.isEqual(nil, nil))

        let element = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        XCTAssertFalse(AXElementComparison.isEqual(nil, element))
        XCTAssertFalse(AXElementComparison.isEqual(element, nil))
        XCTAssertTrue(AXElementComparison.isEqual(element, element))
    }

    func testWindowZOrderFollowsFrontToBackWindowServerIDs() {
        let back = window(1, cgWindowID: 11)
        let front = window(2, cgWindowID: 22)
        let unmatched = window(3, cgWindowID: 33)

        let ranked = WindowZOrder.ranked(
            [back, unmatched, front],
            cgWindowIDsFrontToBack: [22, 11]
        )

        XCTAssertEqual(ranked.map(\.id), [front.id, back.id, unmatched.id])
    }

    func testRecentWindowOrderPutsStoredUsageAheadOfZOrder() {
        let ranks = RecentWindowOrder.combinedRanks(
            primaryIDs: [33, 11],
            secondaryIDs: [22, 11, 33]
        )
        XCTAssertEqual(ranks[33], 0)
        XCTAssertEqual(ranks[11], 1)
        XCTAssertEqual(ranks[22], 2)
    }

    func testUsageOrderMarksFrontmostIncludedWindowAsCurrent() {
        let back = window(1, cgWindowID: 11)
        let front = window(2, cgWindowID: 22)
        let marked = WindowUsageOrder.markedCurrent(
            [back, front],
            frontToBackCGWindowIDs: [22, 11]
        )

        XCTAssertEqual(marked.map(\.isCurrent), [false, true])
        XCTAssertEqual(
            WindowUsageOrder.idsFrontToBack(onScreen: [22, 11], remaining: [11, 33]),
            [22, 11, 33]
        )
    }

    func testScanTraceReportsDuplicateCGWindowIDsAndOnScreenAlignment() {
        let first = window(1, cgWindowID: 11)
        let second = window(2, cgWindowID: 11)
        let third = window(3, cgWindowID: 33)

        XCTAssertEqual(WindowScanTrace.duplicateCGWindowIDs(in: [first, second, third]), [11])
        XCTAssertEqual(
            WindowScanTrace.onScreenIDs(in: [third, first], matching: [11, 33, 44]),
            [33, 11]
        )
        XCTAssertTrue(WindowScanTrace.summary(records: [first, second]).contains("duplicateCG=11"))
    }

    func testFrontmostCGWindowIDUsesFirstOnScreenWindowForPID() {
        let windowID = RecentWindowOrder.frontmostCGWindowID(
            for: 10,
            frontToBackCGWindowIDs: [1, 2, 3],
            snapshots: [(id: 1, pid: 9), (id: 2, pid: 10), (id: 3, pid: 10)]
        )
        XCTAssertEqual(windowID, 2)
    }

    func testCurrentApplicationDialogsRemainIncluded() {
        XCTAssertTrue(
            WindowInclusion.allowsDialog(true, includesDialogs: false, belongsToCurrentApplication: true)
        )
        XCTAssertFalse(
            WindowInclusion.allowsDialog(true, includesDialogs: false, belongsToCurrentApplication: false)
        )
        XCTAssertTrue(
            WindowInclusion.allowsDialog(false, includesDialogs: false, belongsToCurrentApplication: false)
        )
    }

    func testOwnOverlayWindowsWithoutLayerZeroAreExcluded() {
        XCTAssertTrue(
            WindowInclusion.allowsOwnApplicationWindow(isOwnApplication: true, windowServerLayer: 0)
        )
        XCTAssertFalse(
            WindowInclusion.allowsOwnApplicationWindow(isOwnApplication: true, windowServerLayer: nil)
        )
        XCTAssertFalse(
            WindowInclusion.allowsOwnApplicationWindow(isOwnApplication: true, windowServerLayer: 25)
        )
        XCTAssertTrue(
            WindowInclusion.allowsOwnApplicationWindow(isOwnApplication: false, windowServerLayer: nil)
        )
    }

    private func window(_ generation: UInt64, cgWindowID: CGWindowID) -> WindowRecord {
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
