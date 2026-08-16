import ApplicationServices
import XCTest
@testable import TabFlow

final class PermissionManagerTests: XCTestCase {
    func testAccessibilityTrustUsesLiveProbeInsteadOfStaleProcessFlag() {
        XCTAssertTrue(
            AccessibilityTrustReading.isGranted(
                processTrusted: false,
                systemWideAttributeError: .success
            )
        )
        XCTAssertFalse(
            AccessibilityTrustReading.isGranted(
                processTrusted: true,
                systemWideAttributeError: .apiDisabled
            )
        )
    }

    func testAccessibilityTrustFallsBackToProcessFlagWhenProbeIsTransient() {
        XCTAssertTrue(
            AccessibilityTrustReading.isGranted(
                processTrusted: true,
                systemWideAttributeError: .cannotComplete
            )
        )
        XCTAssertFalse(
            AccessibilityTrustReading.isGranted(
                processTrusted: false,
                systemWideAttributeError: .cannotComplete
            )
        )
    }

    func testAccessibilityAPIChangeIsSettledBeforeReadingTrust() {
        XCTAssertFalse(AccessibilityTrustReading.settleDelays.isEmpty)
        XCTAssertGreaterThan(AccessibilityTrustReading.settleDelays[0], .zero)
        XCTAssertEqual(
            AccessibilityTrustReading.apiChangeNotification.rawValue,
            "com.apple.accessibility.api"
        )
    }
}
