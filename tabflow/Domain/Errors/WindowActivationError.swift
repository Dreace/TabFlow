import AppKit
import ApplicationServices
import Foundation

enum WindowActivationError: LocalizedError {
    case windowClosed(applicationName: String, title: String)
    case applicationExited(applicationName: String)
    case couldNotBringToFront(applicationName: String, title: String, reason: String)

    var errorDescription: String? {
        switch self {
        case let .windowClosed(applicationName, title):
            String(
                format: String(localized: "error.windowClosed.format"),
                locale: .current,
                applicationName,
                title
            )
        case let .applicationExited(applicationName):
            String(
                format: String(localized: "error.applicationExited.format"),
                locale: .current,
                applicationName
            )
        case let .couldNotBringToFront(applicationName, title, reason):
            String(
                format: String(localized: "error.activationFailed.format"),
                locale: .current,
                applicationName,
                title,
                reason
            )
        }
    }
}

nonisolated enum WindowActivationPolicy {
    static func processHasExited(_ application: NSRunningApplication?) -> Bool {
        application == nil || application?.isTerminated == true
    }

    static func didBringApplicationForward(
        activateReturned: Bool,
        isActive: Bool,
        isFrontmost: Bool
    ) -> Bool {
        activateReturned || isActive || isFrontmost
    }

    static func didActivateTargetWindow(
        didBringApplicationForward: Bool,
        raiseSucceeded: Bool,
        focusedWindowMatches: Bool,
        windowIsFrontForProcess: Bool,
        canVerifyWindowFront: Bool
    ) -> Bool {
        guard didBringApplicationForward else { return false }
        if focusedWindowMatches || windowIsFrontForProcess { return true }
        if canVerifyWindowFront { return false }
        return raiseSucceeded
    }

    static func failureReason(
        didBringApplicationForward: Bool,
        raiseError: AXError?
    ) -> String {
        if !didBringApplicationForward {
            return String(localized: "error.activationFailed.activateRefused")
        }
        if let raiseError, raiseError != .success {
            return raiseFailureReason(raiseError)
        }
        return String(localized: "error.activationFailed.windowNotRaised")
    }

    static func raiseFailureReason(_ error: AXError) -> String {
        switch error {
        case .apiDisabled:
            String(localized: "error.activationFailed.permission")
        case .cannotComplete:
            String(localized: "error.activationFailed.unresponsive")
        case .invalidUIElement:
            String(localized: "error.activationFailed.windowInvalid")
        case .actionUnsupported:
            String(localized: "error.activationFailed.raiseUnsupported")
        default:
            String(
                format: String(localized: "error.activationFailed.raiseFailed.format"),
                locale: .current,
                error.diagnosticName
            )
        }
    }
}

nonisolated enum WindowActivationSequence {
    static func shouldBringApplicationForward(isFrontmost: Bool, isHidden: Bool) -> Bool {
        !isFrontmost || isHidden
    }

    static func shouldActivateAfterRaise() -> Bool {
        false
    }

    static func shouldHideOverlayBeforeActivation() -> Bool {
        true
    }

    static func shouldRefocusAfterOverlayDismiss() -> Bool {
        true
    }
}

nonisolated enum WindowRaiseRetryPolicy {
    static let delay: Duration = .milliseconds(50)
    static let maxRaiseAttempts = 4

    static func shouldRetry(targetConfirmed: Bool, raiseAttemptsUsed: Int) -> Bool {
        !targetConfirmed && raiseAttemptsUsed < maxRaiseAttempts
    }
}
