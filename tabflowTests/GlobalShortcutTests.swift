import AppKit
import XCTest
@testable import TabFlow

final class GlobalShortcutTests: XCTestCase {
    func testDisplayNameUsesStoredModifiersAndKey() {
        let shortcut = GlobalShortcut(
            keyCode: 48,
            modifiersRawValue: CGEventFlags.maskControl.union(.maskAlternate).rawValue
        )

        XCTAssertEqual(shortcut.displayName, "⌃ ⌥ Tab")
    }

    func testKnownSystemConflictDetection() {
        let commandTab = GlobalShortcut(
            keyCode: 48,
            modifiersRawValue: CGEventFlags.maskCommand.rawValue
        )
        let commandSpace = GlobalShortcut(
            keyCode: 49,
            modifiersRawValue: CGEventFlags.maskCommand.rawValue
        )

        XCTAssertTrue(commandTab.hasKnownSystemConflict)
        XCTAssertTrue(commandSpace.hasKnownSystemConflict)
        XCTAssertFalse(GlobalShortcut.defaultSwitcher.hasKnownSystemConflict)
    }

    func testOnboardingShortcutProbeRequiresARecognizedPress() {
        XCTAssertEqual(
            OnboardingShortcutProbe.status(
                hasSystemConflict: false,
                eventTapAvailable: true,
                didRecognizeShortcut: false
            ),
            .waiting
        )
        XCTAssertEqual(
            OnboardingShortcutProbe.status(
                hasSystemConflict: false,
                eventTapAvailable: true,
                didRecognizeShortcut: true
            ),
            .succeeded
        )
        XCTAssertEqual(
            OnboardingShortcutProbe.status(
                hasSystemConflict: true,
                eventTapAvailable: true,
                didRecognizeShortcut: true
            ),
            .conflict
        )
        XCTAssertEqual(
            OnboardingShortcutProbe.status(
                hasSystemConflict: false,
                eventTapAvailable: false,
                didRecognizeShortcut: false
            ),
            .unavailable
        )
        XCTAssertFalse(OnboardingShortcutProbe.canContinue(.waiting))
        XCTAssertTrue(OnboardingShortcutProbe.canContinue(.succeeded))
    }

    func testModifierReleaseDoesNotCommitWhileSearchQueryIsActive() {
        XCTAssertTrue(
            ModifierReleasePolicy.commitsSwitcher(confirmsOnRelease: true, hasSearchQuery: false)
        )
        XCTAssertFalse(
            ModifierReleasePolicy.commitsSwitcher(confirmsOnRelease: true, hasSearchQuery: true)
        )
        XCTAssertFalse(
            ModifierReleasePolicy.commitsSwitcher(confirmsOnRelease: false, hasSearchQuery: false)
        )
    }
}
