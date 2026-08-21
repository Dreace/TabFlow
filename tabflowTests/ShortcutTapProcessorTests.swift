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

    func testCapturingShortcutSwallowsReservedCombosAndReturnsTheShortcut() {
        var snapshot = ShortcutTapSnapshot()
        snapshot.isCapturingShortcut = true
        snapshot.isSwitcherVisible = true
        let optionTab = ShortcutTapProcessor.handle(
            type: .keyDown,
            keyCode: 48,
            flags: .maskAlternate,
            characters: nil,
            snapshot: &snapshot
        )
        let commandTab = ShortcutTapProcessor.handle(
            type: .keyDown,
            keyCode: 48,
            flags: .maskCommand,
            characters: nil,
            snapshot: &snapshot
        )

        XCTAssertFalse(optionTab.passEvent)
        XCTAssertEqual(
            optionTab.capturedShortcut,
            GlobalShortcut(keyCode: 48, modifiersRawValue: CGEventFlags.maskAlternate.rawValue)
        )
        XCTAssertFalse(commandTab.passEvent)
        XCTAssertEqual(
            commandTab.capturedShortcut,
            GlobalShortcut(keyCode: 48, modifiersRawValue: CGEventFlags.maskCommand.rawValue)
        )
        XCTAssertNil(optionTab.action)
        XCTAssertFalse(optionTab.probeRecognized)
    }

    func testCapturingShortcutPassesEscapeAndDeleteThroughToTheRecorder() {
        var snapshot = ShortcutTapSnapshot()
        snapshot.isCapturingShortcut = true
        let escape = ShortcutTapProcessor.handle(
            type: .keyDown,
            keyCode: 53,
            flags: .maskCommand,
            characters: nil,
            snapshot: &snapshot
        )
        let delete = ShortcutTapProcessor.handle(
            type: .keyDown,
            keyCode: 51,
            flags: [],
            characters: nil,
            snapshot: &snapshot
        )

        XCTAssertTrue(escape.passEvent)
        XCTAssertNil(escape.capturedShortcut)
        XCTAssertTrue(delete.passEvent)
        XCTAssertNil(delete.capturedShortcut)
    }

    func testClearedShortcutDoesNotOpenTheSwitcher() {
        var snapshot = ShortcutTapSnapshot()
        snapshot.shortcut = .none
        let outcome = ShortcutTapProcessor.handle(
            type: .keyDown,
            keyCode: 0,
            flags: [],
            characters: nil,
            snapshot: &snapshot
        )

        XCTAssertTrue(outcome.passEvent)
        XCTAssertNil(outcome.action)
        XCTAssertFalse(snapshot.isSwitcherVisible)
    }

    func testEventTapUsesSessionLocation() {
        XCTAssertEqual(
            ShortcutEventTapPlacement.locations,
            [.cgSessionEventTap]
        )
        XCTAssertTrue(ShortcutTapLifecycle.invalidatesEventTapOnStop())
        XCTAssertTrue(ShortcutTapLifecycle.drainsAutoreleasePoolPerEvent())
        XCTAssertEqual(
            ShortcutTapLifecycle.machPortTeardownOrder,
            [.disableTap, .stopRunLoop, .removeSource, .invalidatePort]
        )
    }
}
