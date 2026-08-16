import CoreGraphics
import XCTest
@testable import TabFlow

final class ShortcutTapProcessorTests: XCTestCase {
    func testShortcutKeyDownCyclesForwardAndMarksSwitcherVisible() {
        var snapshot = ShortcutTapSnapshot()
        let outcome = ShortcutTapProcessor.handle(
            type: .keyDown,
            keyCode: 48,
            flags: .maskAlternate,
            characters: nil,
            snapshot: &snapshot
        )

        XCTAssertFalse(outcome.passEvent)
        XCTAssertEqual(outcome.action, .cycle(.forward))
        XCTAssertTrue(snapshot.isSwitcherVisible)
        XCTAssertTrue(snapshot.optionWasDown)
    }

    func testModifierReleaseCommitsWhenSwitcherIsVisible() {
        var snapshot = ShortcutTapSnapshot()
        snapshot.isSwitcherVisible = true
        snapshot.optionWasDown = true
        let outcome = ShortcutTapProcessor.handle(
            type: .flagsChanged,
            keyCode: 0,
            flags: [],
            characters: nil,
            snapshot: &snapshot
        )

        XCTAssertFalse(outcome.passEvent)
        XCTAssertEqual(outcome.action, .commit)
        XCTAssertFalse(snapshot.optionWasDown)
    }

    func testEscapeCancelsWhileSwitcherIsVisible() {
        var snapshot = ShortcutTapSnapshot()
        snapshot.isSwitcherVisible = true
        let outcome = ShortcutTapProcessor.handle(
            type: .keyDown,
            keyCode: 53,
            flags: [],
            characters: nil,
            snapshot: &snapshot
        )

        XCTAssertFalse(outcome.passEvent)
        XCTAssertEqual(outcome.action, .cancel)
    }

    func testPausedTapPassesEventsThrough() {
        var snapshot = ShortcutTapSnapshot()
        snapshot.isPaused = true
        snapshot.isSwitcherVisible = true
        let outcome = ShortcutTapProcessor.handle(
            type: .keyDown,
            keyCode: 53,
            flags: [],
            characters: nil,
            snapshot: &snapshot
        )

        XCTAssertTrue(outcome.passEvent)
        XCTAssertNil(outcome.action)
    }

    func testProbeRecognizesShortcutWithoutCycling() {
        var snapshot = ShortcutTapSnapshot()
        snapshot.isProbingShortcut = true
        let outcome = ShortcutTapProcessor.handle(
            type: .keyDown,
            keyCode: 48,
            flags: .maskAlternate,
            characters: nil,
            snapshot: &snapshot
        )

        XCTAssertTrue(outcome.probeRecognized)
        XCTAssertNil(outcome.action)
        XCTAssertFalse(snapshot.isSwitcherVisible)
        XCTAssertFalse(outcome.passEvent)
    }

    func testEventTapLifecycleReleasesPortsAndAutoreleasePools() {
        XCTAssertTrue(ShortcutTapLifecycle.invalidatesEventTapOnStop())
        XCTAssertTrue(ShortcutTapLifecycle.drainsAutoreleasePoolPerEvent())
    }
}
