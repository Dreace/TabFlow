import CoreGraphics
import XCTest
@testable import TabFlow

final class ShortcutConflictDetectorTests: XCTestCase {
    func testKnownSystemShortcutsAreReportedAsPossibleConflicts() {
        XCTAssertEqual(
            ShortcutConflictDetector.conflict(for: KnownSystemShortcut.appSwitcher.shortcut),
            .knownSystem(KnownSystemShortcut.appSwitcher.reason)
        )
        XCTAssertEqual(
            ShortcutConflictDetector.conflict(for: KnownSystemShortcut.spotlight.shortcut),
            .knownSystem(KnownSystemShortcut.spotlight.reason)
        )
        XCTAssertEqual(
            ShortcutConflictDetector.conflict(for: KnownSystemShortcut.missionControl.shortcut),
            .knownSystem(KnownSystemShortcut.missionControl.reason)
        )
        XCTAssertEqual(
            ShortcutConflictDetector.conflict(for: .defaultSwitcher),
            .none
        )
    }

    func testTabFlowOwnedShortcutsTakePriorityOverSystemAndRegistrationProbes() {
        let owned = ShortcutConflictDetector.OwnedShortcut(
            shortcut: KnownSystemShortcut.appSwitcher.shortcut,
            name: "forward"
        )
        XCTAssertEqual(
            ShortcutConflictDetector.conflict(
                for: owned.shortcut,
                existing: [owned],
                registeredElsewhere: true
            ),
            .tabFlow("forward")
        )
    }

    func testCarbonRegistrationIsOnlyASupplementaryConflict() {
        XCTAssertEqual(
            ShortcutConflictDetector.conflict(
                for: .defaultSwitcher,
                registeredElsewhere: true
            ),
            .registeredElsewhere
        )
        XCTAssertEqual(
            ShortcutConflictDetector.conflict(for: .none, registeredElsewhere: true),
            .none
        )
    }
}

final class ShortcutRecorderPolicyTests: XCTestCase {
    func testEscapeCancelsRecording() {
        XCTAssertEqual(
            ShortcutRecorderPolicy.handleKeyDown(keyCode: 53, modifierFlags: [.option]),
            .cancel
        )
    }

    func testDeleteClearsTheShortcut() {
        XCTAssertEqual(
            ShortcutRecorderPolicy.handleKeyDown(keyCode: 51, modifierFlags: []),
            .clear
        )
        XCTAssertEqual(
            ShortcutRecorderPolicy.handleKeyDown(keyCode: 117, modifierFlags: [.command]),
            .clear
        )
    }

    func testKeyDownCapturesPhysicalKeyCodeAndModifiersWithoutShift() {
        guard case let .capture(shortcut) = ShortcutRecorderPolicy.handleKeyDown(
            keyCode: 48,
            modifierFlags: [.option, .shift]
        ) else {
            XCTFail("Expected a captured shortcut")
            return
        }
        XCTAssertEqual(shortcut.keyCode, 48)
        XCTAssertEqual(shortcut.eventFlags, .maskAlternate)
        XCTAssertTrue(shortcut.isConfigured)
    }

    func testModifierOnlyPressesAreInvalid() {
        XCTAssertEqual(
            ShortcutRecorderPolicy.handleKeyDown(keyCode: 48, modifierFlags: [.shift]),
            .invalid
        )
    }

    func testRecordingEndsWhenTheRecorderWindowGoesAway() {
        XCTAssertTrue(
            ShortcutRecorderLifecycle.shouldEndRecording(
                windowBecameNil: true,
                windowWillClose: false,
                windowResignedKey: false
            )
        )
        XCTAssertTrue(
            ShortcutRecorderLifecycle.shouldEndRecording(
                windowBecameNil: false,
                windowWillClose: true,
                windowResignedKey: false
            )
        )
        XCTAssertTrue(
            ShortcutRecorderLifecycle.shouldEndRecording(
                windowBecameNil: false,
                windowWillClose: false,
                windowResignedKey: true
            )
        )
        XCTAssertFalse(
            ShortcutRecorderLifecycle.shouldEndRecording(
                windowBecameNil: false,
                windowWillClose: false,
                windowResignedKey: false
            )
        )
    }
}
