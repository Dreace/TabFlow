import AppKit
import Carbon.HIToolbox
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

    func testDisplayNameUsesLettersAndDigitsInsteadOfKeyCodes() {
        let letter = GlobalShortcut(
            keyCode: Int64(kVK_ANSI_A),
            modifiersRawValue: CGEventFlags.maskCommand.rawValue
        )
        let digit = GlobalShortcut(
            keyCode: Int64(kVK_ANSI_1),
            modifiersRawValue: CGEventFlags.maskAlternate.rawValue
        )

        XCTAssertEqual(letter.displayName, "⌘ A")
        XCTAssertEqual(digit.displayName, "⌥ 1")
        XCTAssertEqual(ShortcutKeyName.displayName(for: Int64(kVK_ANSI_Z)), "Z")
        XCTAssertEqual(ShortcutKeyName.displayName(for: Int64(kVK_ANSI_0)), "0")
    }

    func testCommandTabIsDetectedWithoutShift() {
        let commandTab = GlobalShortcut(
            keyCode: 48,
            modifiersRawValue: CGEventFlags.maskCommand.rawValue
        )
        XCTAssertTrue(NativeCommandTabHotKey.matches(commandTab))
        XCTAssertTrue(
            NativeCommandTabHotKey.shouldSuppress(
                shortcut: commandTab,
                isCapturing: false,
                isTapRunning: true
            )
        )
        XCTAssertTrue(
            NativeCommandTabHotKey.shouldSuppress(
                shortcut: .defaultSwitcher,
                isCapturing: true,
                isTapRunning: false
            )
        )
        XCTAssertFalse(
            NativeCommandTabHotKey.shouldSuppress(
                shortcut: .defaultSwitcher,
                isCapturing: false,
                isTapRunning: false
            )
        )
        XCTAssertFalse(
            NativeCommandTabHotKey.shouldSuppress(
                shortcut: commandTab,
                isCapturing: false,
                isTapRunning: false
            )
        )
        XCTAssertEqual(
            GlobalShortcut.from(eventFlags: .maskCommand, keyCode: 48),
            commandTab
        )
    }

    func testClearedShortcutIsNotConfigured() {
        XCTAssertFalse(GlobalShortcut.none.isConfigured)
        XCTAssertEqual(GlobalShortcut.none.displayName, String(localized: "shortcut.none"))
    }

    func testOnboardingShortcutProbeRequiresARecognizedPress() {
        XCTAssertEqual(
            OnboardingShortcutProbe.status(
                eventTapAvailable: true,
                didRecognizeShortcut: false
            ),
            .waiting
        )
        XCTAssertEqual(
            OnboardingShortcutProbe.status(
                eventTapAvailable: true,
                didRecognizeShortcut: true
            ),
            .succeeded
        )
        XCTAssertEqual(
            OnboardingShortcutProbe.status(
                eventTapAvailable: false,
                didRecognizeShortcut: false
            ),
            .unavailable
        )
        XCTAssertFalse(OnboardingShortcutProbe.canContinue(.waiting))
        XCTAssertTrue(OnboardingShortcutProbe.canContinue(.succeeded))
        XCTAssertTrue(
            OnboardingShortcutProbe.canContinue(
                OnboardingShortcutProbe.status(
                    eventTapAvailable: true,
                    didRecognizeShortcut: true
                )
            )
        )
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
