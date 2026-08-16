import AppKit
import ApplicationServices
import XCTest
@testable import TabFlow

final class WindowActivationTests: XCTestCase {
    func testProcessHasExitedWhenApplicationIsMissing() {
        XCTAssertTrue(WindowActivationPolicy.processHasExited(nil))
        XCTAssertFalse(
            WindowActivationPolicy.processHasExited(NSRunningApplication.current)
        )
    }

    func testActivationSucceedsIfProcessIsAlreadyFrontmost() {
        XCTAssertTrue(
            WindowActivationPolicy.didBringApplicationForward(
                activateReturned: false,
                isActive: true,
                isFrontmost: false
            )
        )
        XCTAssertTrue(
            WindowActivationPolicy.didBringApplicationForward(
                activateReturned: false,
                isActive: false,
                isFrontmost: true
            )
        )
        XCTAssertFalse(
            WindowActivationPolicy.didBringApplicationForward(
                activateReturned: false,
                isActive: false,
                isFrontmost: false
            )
        )
    }

    func testActivationRequiresTargetWindowRaiseOrFocusMatch() {
        XCTAssertTrue(
            WindowActivationPolicy.didActivateTargetWindow(
                didBringApplicationForward: true,
                raiseSucceeded: true,
                focusedWindowMatches: false,
                windowIsFrontForProcess: false,
                canVerifyWindowFront: false
            )
        )
        XCTAssertTrue(
            WindowActivationPolicy.didActivateTargetWindow(
                didBringApplicationForward: true,
                raiseSucceeded: false,
                focusedWindowMatches: true,
                windowIsFrontForProcess: false,
                canVerifyWindowFront: true
            )
        )
        XCTAssertTrue(
            WindowActivationPolicy.didActivateTargetWindow(
                didBringApplicationForward: true,
                raiseSucceeded: true,
                focusedWindowMatches: false,
                windowIsFrontForProcess: true,
                canVerifyWindowFront: true
            )
        )
        XCTAssertFalse(
            WindowActivationPolicy.didActivateTargetWindow(
                didBringApplicationForward: true,
                raiseSucceeded: true,
                focusedWindowMatches: false,
                windowIsFrontForProcess: false,
                canVerifyWindowFront: true
            )
        )
        XCTAssertFalse(
            WindowActivationPolicy.didActivateTargetWindow(
                didBringApplicationForward: true,
                raiseSucceeded: false,
                focusedWindowMatches: false,
                windowIsFrontForProcess: false,
                canVerifyWindowFront: false
            )
        )
        XCTAssertFalse(
            WindowActivationPolicy.didActivateTargetWindow(
                didBringApplicationForward: false,
                raiseSucceeded: true,
                focusedWindowMatches: true,
                windowIsFrontForProcess: true,
                canVerifyWindowFront: true
            )
        )
    }

    func testRaiseSuccessIsNotEnoughWhenSameProcessFrontWindowCanBeVerified() {
        XCTAssertFalse(
            WindowActivationPolicy.didActivateTargetWindow(
                didBringApplicationForward: true,
                raiseSucceeded: true,
                focusedWindowMatches: false,
                windowIsFrontForProcess: false,
                canVerifyWindowFront: true
            )
        )
        XCTAssertEqual(
            WindowActivationPolicy.failureReason(
                didBringApplicationForward: true,
                raiseError: .success
            ),
            String(localized: "error.activationFailed.windowNotRaised")
        )
    }

    func testRaiseRetryStopsOnceTargetIsConfirmed() {
        XCTAssertTrue(
            WindowRaiseRetryPolicy.shouldRetry(targetConfirmed: false, raiseAttemptsUsed: 1)
        )
        XCTAssertTrue(
            WindowRaiseRetryPolicy.shouldRetry(targetConfirmed: false, raiseAttemptsUsed: 3)
        )
        XCTAssertFalse(
            WindowRaiseRetryPolicy.shouldRetry(targetConfirmed: true, raiseAttemptsUsed: 1)
        )
        XCTAssertFalse(
            WindowRaiseRetryPolicy.shouldRetry(targetConfirmed: false, raiseAttemptsUsed: 4)
        )
    }

    func testOwnApplicationWindowMatchPrefersWindowNumberThenTitle() {
        XCTAssertTrue(
            OwnApplicationWindowMatch.isCandidate(styleMaskContainsTitled: true, isSheet: false)
        )
        XCTAssertFalse(
            OwnApplicationWindowMatch.isCandidate(styleMaskContainsTitled: false, isSheet: false)
        )
        XCTAssertFalse(
            OwnApplicationWindowMatch.isCandidate(styleMaskContainsTitled: true, isSheet: true)
        )
        XCTAssertEqual(
            OwnApplicationWindowMatch.index(
                windowNumbers: [11, 22, 33],
                titles: ["Onboarding", "Settings", "About"],
                cgWindowID: 22,
                recordTitle: "About"
            ),
            1
        )
        XCTAssertEqual(
            OwnApplicationWindowMatch.index(
                windowNumbers: [11, 22, 33],
                titles: ["Onboarding", "Settings", "About"],
                cgWindowID: 99,
                recordTitle: " Settings "
            ),
            1
        )
        XCTAssertNil(
            OwnApplicationWindowMatch.index(
                windowNumbers: [11, 22],
                titles: ["Onboarding", "Settings"],
                cgWindowID: 99,
                recordTitle: ""
            )
        )
    }

    func testActivationDoesNotActivateTheAppAgainAfterRaise() {
        XCTAssertFalse(WindowActivationSequence.shouldActivateAfterRaise())
        XCTAssertTrue(WindowActivationSequence.shouldHideOverlayBeforeActivation())
        XCTAssertTrue(WindowActivationSequence.shouldRefocusAfterOverlayDismiss())
        XCTAssertTrue(
            WindowActivationSequence.shouldBringApplicationForward(isFrontmost: false, isHidden: false)
        )
        XCTAssertFalse(
            WindowActivationSequence.shouldBringApplicationForward(isFrontmost: true, isHidden: false)
        )
        XCTAssertTrue(
            WindowActivationSequence.shouldBringApplicationForward(isFrontmost: true, isHidden: true)
        )
    }

    func testWindowServerFocusSkipsApplicationActivateWhenAWindowIDIsAvailable() {
        XCTAssertTrue(WindowServerFocusPolicy.canFocusSpecificWindow(cgWindowID: 42))
        XCTAssertFalse(WindowServerFocusPolicy.canFocusSpecificWindow(cgWindowID: nil))
        XCTAssertFalse(WindowServerFocusPolicy.shouldClearWindowsBeforeFocus())
        XCTAssertTrue(
            WindowServerFocusPolicy.shouldResignCurrentKeyWindow(
                currentFrontWindowID: 11,
                targetWindowID: 22
            )
        )
        XCTAssertFalse(
            WindowServerFocusPolicy.shouldResignCurrentKeyWindow(
                currentFrontWindowID: 22,
                targetWindowID: 22
            )
        )
        XCTAssertFalse(
            WindowServerFocusPolicy.shouldResignCurrentKeyWindow(
                currentFrontWindowID: nil,
                targetWindowID: 22
            )
        )
        XCTAssertFalse(
            WindowServerFocusPolicy.shouldActivateApplication(
                hasWindowID: true,
                isFrontmost: true,
                isHidden: false
            )
        )
        XCTAssertFalse(
            WindowServerFocusPolicy.shouldActivateApplication(
                hasWindowID: true,
                isFrontmost: false,
                isHidden: false
            )
        )
        XCTAssertTrue(
            WindowServerFocusPolicy.shouldActivateApplication(
                hasWindowID: false,
                isFrontmost: false,
                isHidden: false
            )
        )
    }

    func testWindowFrontVerificationRequiresMatchingCGWindowID() {
        XCTAssertTrue(WindowFrontVerification.isFront(targetID: 12, frontmostIDForProcess: 12))
        XCTAssertFalse(WindowFrontVerification.isFront(targetID: 12, frontmostIDForProcess: 13))
        XCTAssertFalse(WindowFrontVerification.isFront(targetID: 12, frontmostIDForProcess: nil))
        XCTAssertFalse(WindowFrontVerification.isFront(targetID: nil, frontmostIDForProcess: 12))
    }

    func testWindowMenuMatchingAcceptsNumberedAndPrefixTitles() {
        XCTAssertGreaterThan(
            WindowMenuRaiseMatching.score(
                recordTitle: "App.swift — tabflow",
                menuItemTitle: "App.swift — tabflow"
            ),
            0
        )
        XCTAssertGreaterThan(
            WindowMenuRaiseMatching.score(
                recordTitle: "App.swift — tabflow — Visual Studio Code",
                menuItemTitle: "1 App.swift — tabflow"
            ),
            0
        )
        XCTAssertEqual(
            WindowMenuRaiseMatching.score(recordTitle: "Inbox", menuItemTitle: "Zoom"),
            0
        )
        XCTAssertEqual(
            WindowMenuRaiseMatching.score(recordTitle: "Inbox", menuItemTitle: "Minimize"),
            0
        )
    }

    func testRaiseMatchingScoreAcceptsPrefixedApplicationTitles() {
        let frame = CGRect(x: 10, y: 20, width: 800, height: 600)
        XCTAssertGreaterThan(
            WindowRaiseMatching.score(
                recordTitle: "App.swift — tabflow",
                recordFrame: frame,
                windowTitle: "App.swift — tabflow — Visual Studio Code",
                windowFrame: frame
            ),
            0
        )
        XCTAssertEqual(
            WindowRaiseMatching.score(
                recordTitle: "Inbox",
                recordFrame: frame,
                windowTitle: "Sent",
                windowFrame: frame
            ),
            0
        )
    }

    func testActivationFailureReasonWhenRaiseNeverRan() {
        XCTAssertEqual(
            WindowActivationPolicy.failureReason(
                didBringApplicationForward: true,
                raiseError: nil
            ),
            String(localized: "error.activationFailed.windowNotRaised")
        )
    }

    func testRaiseMatchingRequiresTitleOrCloseGeometryWhenUntitled() {
        let frame = CGRect(x: 10, y: 20, width: 800, height: 600)
        XCTAssertTrue(
            WindowRaiseMatching.matches(
                recordTitle: "Inbox",
                recordFrame: frame,
                windowTitle: "Inbox",
                windowFrame: frame.offsetBy(dx: 400, dy: 400)
            )
        )
        XCTAssertFalse(
            WindowRaiseMatching.matches(
                recordTitle: "Inbox",
                recordFrame: frame,
                windowTitle: "Sent",
                windowFrame: frame
            )
        )
        XCTAssertFalse(
            WindowRaiseMatching.matches(
                recordTitle: "Inbox",
                recordFrame: frame,
                windowTitle: "",
                windowFrame: frame
            )
        )
        XCTAssertTrue(
            WindowRaiseMatching.matches(
                recordTitle: "",
                recordFrame: frame,
                windowTitle: "",
                windowFrame: frame.offsetBy(dx: 4, dy: 8)
            )
        )
        XCTAssertFalse(
            WindowRaiseMatching.matches(
                recordTitle: "",
                recordFrame: frame,
                windowTitle: "",
                windowFrame: frame.offsetBy(dx: 400, dy: 400)
            )
        )
    }

    func testActivationErrorsIncludeApplicationAndWindowIdentity() {
        let closed = WindowActivationError.windowClosed(
            applicationName: "Safari",
            title: "Start Page"
        )
        XCTAssertEqual(
            closed.errorDescription,
            String(
                format: String(localized: "error.windowClosed.format"),
                locale: .current,
                "Safari",
                "Start Page"
            )
        )

        let refused = WindowActivationError.couldNotBringToFront(
            applicationName: "Xcode",
            title: "TabFlow",
            reason: String(localized: "error.activationFailed.activateRefused")
        )
        XCTAssertEqual(
            refused.errorDescription,
            String(
                format: String(localized: "error.activationFailed.format"),
                locale: .current,
                "Xcode",
                "TabFlow",
                String(localized: "error.activationFailed.activateRefused")
            )
        )
        XCTAssertTrue(refused.errorDescription?.contains("Xcode") == true)
        XCTAssertTrue(refused.errorDescription?.contains("TabFlow") == true)
        XCTAssertNotEqual(refused.errorDescription, String(localized: "error.activationFailed"))
    }

    func testRaiseFailureReasonUsesPermissionAndTransientCodes() {
        XCTAssertEqual(
            WindowActivationPolicy.raiseFailureReason(.apiDisabled),
            String(localized: "error.activationFailed.permission")
        )
        XCTAssertEqual(
            WindowActivationPolicy.raiseFailureReason(.cannotComplete),
            String(localized: "error.activationFailed.unresponsive")
        )
    }
}
