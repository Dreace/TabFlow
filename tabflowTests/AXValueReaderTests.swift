import ApplicationServices
import XCTest
@testable import TabFlow

final class AXValueReaderTests: XCTestCase {
    func testCannotCompleteIsATransientWindowListFailure() {
        XCTAssertEqual(AXWindowListFailureKind(code: .cannotComplete), .transient)
        XCTAssertEqual(
            AXReadError.failure(attribute: "AXWindows", code: .cannotComplete).windowListFailureKind,
            .transient
        )
    }

    func testMissingOrUnsupportedWindowListsAreNotFatal() {
        XCTAssertEqual(AXWindowListFailureKind(code: .noValue), .unsupported)
        XCTAssertEqual(AXWindowListFailureKind(code: .attributeUnsupported), .unsupported)
        XCTAssertEqual(AXWindowListFailureKind(code: .notImplemented), .unsupported)
        XCTAssertEqual(AXWindowListFailureKind(code: .invalidUIElement), .unsupported)
    }

    func testAPIDisabledWindowListFailureIsFatal() {
        XCTAssertEqual(AXWindowListFailureKind(code: .apiDisabled), .fatal)
        XCTAssertEqual(AXWindowListFailureKind(code: .failure), .fatal)
    }

    func testAXErrorDiagnosticNameUsesCannotCompleteInsteadOfRawBridgeDump() {
        XCTAssertEqual(AXError.cannotComplete.diagnosticName, "cannotComplete")
        XCTAssertEqual(AXError.cannotComplete.rawValue, -25204)
        XCTAssertEqual(
            AXReadError.failure(attribute: "AXWindows", code: .cannotComplete).description,
            "failure(attribute: AXWindows, code: cannotComplete)"
        )
    }

    func testInteractiveScanUsesAShortAccessibilityTimeout() {
        XCTAssertEqual(AXScanLimits.messagingTimeout, 0.15)
        XCTAssertGreaterThan(AXScanLimits.activationTimeout, AXScanLimits.messagingTimeout)
    }

    func testEmptyAXWindowsAttributeFallsBackToChildWindows() {
        XCTAssertTrue(AXWindowEnumeration.shouldUseChildWindows(attributeWindowCount: nil))
        XCTAssertTrue(AXWindowEnumeration.shouldUseChildWindows(attributeWindowCount: 0))
        XCTAssertFalse(AXWindowEnumeration.shouldUseChildWindows(attributeWindowCount: 3))
    }

    func testActivationRetriesWindowListWhenTheFirstReadIsEmpty() {
        XCTAssertTrue(AXActivationRetry.shouldRetry(windowsFound: 0, attempt: 1))
        XCTAssertTrue(AXActivationRetry.shouldRetry(windowsFound: 0, attempt: 3))
        XCTAssertFalse(AXActivationRetry.shouldRetry(windowsFound: 0, attempt: 4))
        XCTAssertFalse(AXActivationRetry.shouldRetry(windowsFound: 2, attempt: 1))
    }

    func testAXWindowListFailuresAreNotRememberedAcrossScans() {
        XCTAssertFalse(AXWindowListRetryPolicy.persistsUnavailablePID(after: .transient))
        XCTAssertFalse(AXWindowListRetryPolicy.persistsUnavailablePID(after: .unsupported))
        XCTAssertFalse(AXWindowListRetryPolicy.persistsUnavailablePID(after: .fatal))
    }

    func testAXWindowIdentityReturnsNilForApplicationElement() {
        let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        XCTAssertNil(AXWindowIdentity.cgWindowID(from: application))
    }

    func testWindowScanRuntimeLeavesTheMainThread() async {
        let ranOnMain = await WindowScanRuntime.runOffMain {
            Thread.isMainThread
        }
        XCTAssertFalse(ranOnMain)
    }

    func testBlockingAXCallsAreIsolatedFromTheMainActor() {
        XCTAssertTrue(AXWorkIsolation.usesDedicatedSerialQueue())
        XCTAssertFalse(AXWorkIsolation.blockingCallsRunOnMainActor())
        XCTAssertTrue(AXWorkIsolation.drainsAutoreleasePoolPerScan())
    }

    func testBackgroundWindowRefreshDoesNotSubscribeToTitleChanges() {
        XCTAssertFalse(AccessibilityObserverPolicy.observesTitleChanges())
        XCTAssertTrue(AccessibilityObserverPolicy.notifications(liveUpdatesEnabled: false).isEmpty)
        XCTAssertFalse(
            AccessibilityObserverPolicy.handlesNotification(
                kAXTitleChangedNotification as String,
                liveUpdatesEnabled: true
            )
        )
        XCTAssertFalse(
            AccessibilityObserverPolicy.handlesNotification(
                kAXWindowCreatedNotification as String,
                liveUpdatesEnabled: false
            )
        )
        XCTAssertTrue(
            AccessibilityObserverPolicy.handlesNotification(
                kAXWindowCreatedNotification as String,
                liveUpdatesEnabled: true
            )
        )
        XCTAssertFalse(
            AccessibilityObserverPolicy.notifications(liveUpdatesEnabled: true).contains {
                ($0 as String) == (kAXTitleChangedNotification as String)
            }
        )
    }

    func testWindowValidityRunsOffTheMainThread() async {
        let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        let ranOnMain = await WindowScanRuntime.runOffMain {
            _ = AXWindowActions.isValid(application)
            return Thread.isMainThread
        }
        XCTAssertFalse(ranOnMain)
    }

    func testOwnProcessRaiseDoesNotPerformAXWritesOffTheMainThread() async {
        XCTAssertTrue(OwnProcessWindowActivation.applies(to: ProcessInfo.processInfo.processIdentifier))
        XCTAssertFalse(OwnProcessWindowActivation.applies(to: 1))
        XCTAssertFalse(OwnProcessWindowActivation.usesAccessibilityRaise())

        let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        let result = await WindowScanRuntime.runOffMain {
            (
                AXWindowActions.raise(
                    application,
                    pid: ProcessInfo.processInfo.processIdentifier
                ),
                Thread.isMainThread
            )
        }
        XCTAssertEqual(result.0, .illegalArgument)
        XCTAssertFalse(result.1)
    }

    func testOwnProcessAXWritesAreRejectedOffTheMainThread() async {
        let application = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        let rejected = await WindowScanRuntime.runOffMain {
            do {
                try AXValueReader.set(
                    kCFBooleanTrue,
                    attribute: kAXFocusedAttribute as CFString,
                    on: application
                )
                return false
            } catch {
                return true
            }
        }
        XCTAssertTrue(rejected)
    }

    func testGenerationIndexDropsClosedProcessesAndStaleElements() {
        let live = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        let stale = AXUIElementCreateApplication(1)
        let closed = AXUIElementCreateApplication(2)
        let generations: [pid_t: [(element: AXUIElement, generation: UInt64)]] = [
            10: [(live, 1), (stale, 2)],
            11: [(closed, 3)]
        ]

        let pruned = AXElementGenerationIndex.pruned(
            generations,
            liveWindows: [(pid: 10, element: live)]
        )

        XCTAssertEqual(pruned[10]?.count, 1)
        XCTAssertEqual(pruned[10]?.first?.generation, 1)
        XCTAssertTrue(pruned[10]?.contains { CFEqual($0.element, live) } == true)
        XCTAssertNil(pruned[11])
    }
}
