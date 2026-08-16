import ApplicationServices
import CoreGraphics
import Foundation

nonisolated enum AXWorkIsolation {
    static func blockingCallsRunOnMainActor() -> Bool { false }

    static func usesDedicatedSerialQueue() -> Bool { true }

    static func drainsAutoreleasePoolPerScan() -> Bool { true }
}

nonisolated enum AccessibilityObserverPolicy {
    static let liveNotifications: [CFString] = [
        kAXFocusedWindowChangedNotification as CFString,
        kAXApplicationHiddenNotification as CFString,
        kAXApplicationShownNotification as CFString,
        kAXWindowCreatedNotification as CFString,
        kAXUIElementDestroyedNotification as CFString,
        kAXWindowMiniaturizedNotification as CFString,
        kAXWindowDeminiaturizedNotification as CFString
    ]

    static func notifications(liveUpdatesEnabled: Bool) -> [CFString] {
        liveUpdatesEnabled ? liveNotifications : []
    }

    static func observesTitleChanges() -> Bool { false }

    static func handlesNotification(_ notification: String, liveUpdatesEnabled: Bool) -> Bool {
        guard liveUpdatesEnabled else { return false }
        return liveNotifications.contains { ($0 as String) == notification }
    }
}

nonisolated struct AXTransfer: @unchecked Sendable {
    let element: AXUIElement
}

nonisolated struct AXWindowMatchResult: @unchecked Sendable {
    let element: AXUIElement?
    let windowCount: Int
}

nonisolated enum OwnProcessWindowActivation {
    static func applies(to pid: pid_t) -> Bool {
        pid == ProcessInfo.processInfo.processIdentifier
    }

    static func usesAccessibilityRaise() -> Bool {
        false
    }
}

nonisolated enum OwnApplicationWindowMatch {
    static func isCandidate(styleMaskContainsTitled: Bool, isSheet: Bool) -> Bool {
        styleMaskContainsTitled && !isSheet
    }

    static func index(
        windowNumbers: [Int],
        titles: [String],
        cgWindowID: CGWindowID?,
        recordTitle: String
    ) -> Int? {
        if let cgWindowID {
            let number = Int(cgWindowID)
            if let index = windowNumbers.firstIndex(of: number) {
                return index
            }
        }
        let title = recordTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        return titles.firstIndex {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) == title
        }
    }
}

nonisolated enum AXWindowActions {
    static func isValid(_ element: AXUIElement) -> Bool {
        AXUIElementSetMessagingTimeout(element, AXScanLimits.messagingTimeout)
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &value
        ) == .success
    }

    static func restoreMinimized(_ element: AXUIElement) {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard !OwnProcessWindowActivation.applies(to: pid) else { return }
        try? AXValueReader.set(
            kCFBooleanFalse,
            attribute: kAXMinimizedAttribute as CFString,
            on: element
        )
    }

    static func raise(_ element: AXUIElement, pid: pid_t) -> AXError {
        guard !OwnProcessWindowActivation.applies(to: pid) else {
            return .illegalArgument
        }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, AXScanLimits.activationTimeout)
        try? AXValueReader.set(element, attribute: kAXFocusedWindowAttribute as CFString, on: application)
        try? AXValueReader.set(element, attribute: kAXMainWindowAttribute as CFString, on: application)
        AXUIElementSetMessagingTimeout(element, AXScanLimits.activationTimeout)
        try? AXValueReader.set(kCFBooleanTrue, attribute: kAXMainAttribute as CFString, on: element)
        try? AXValueReader.set(kCFBooleanTrue, attribute: kAXFocusedAttribute as CFString, on: element)
        return AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    static func focusedWindow(is element: AXUIElement, pid: pid_t) -> Bool {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.3)
        guard let focused = try? AXValueReader.element(
            kAXFocusedWindowAttribute as CFString,
            from: application
        ) else { return false }
        return AXElementComparison.isEqual(focused, element)
    }

    static func focusedElement(pid: pid_t, timeout: Float) -> AXTransfer? {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, timeout)
        guard let element = try? AXValueReader.element(
            kAXFocusedWindowAttribute as CFString,
            from: application
        ) else { return nil }
        return AXTransfer(element: element)
    }

    static func matchingWindow(for record: WindowRecord) -> AXWindowMatchResult {
        let application = AXUIElementCreateApplication(record.pid)
        AXUIElementSetMessagingTimeout(application, AXScanLimits.activationTimeout)
        let windows = (try? AXValueReader.windows(from: application)) ?? []
        let matched = windows
            .compactMap { element -> (AXUIElement, Int)? in
                let title = (try? AXValueReader.string(kAXTitleAttribute as CFString, from: element))?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let position = (try? AXValueReader.point(kAXPositionAttribute as CFString, from: element)) ?? .zero
                let size = (try? AXValueReader.size(kAXSizeAttribute as CFString, from: element)) ?? .zero
                let score = WindowRaiseMatching.score(
                    recordTitle: record.title,
                    recordFrame: record.frame,
                    windowTitle: title,
                    windowFrame: CGRect(origin: position, size: size)
                )
                return score > 0 ? (element, score) : nil
            }
            .max(by: { $0.1 < $1.1 })?
            .0
        return AXWindowMatchResult(element: matched, windowCount: windows.count)
    }
}

nonisolated enum WindowScanRuntime {
    private static let queue = DispatchQueue(
        label: "com.dreace.tabflow.ax",
        qos: .userInitiated
    )

    static func runOffMain<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async {
                let result = autoreleasepool { work() }
                continuation.resume(returning: result)
            }
        }
    }
}

nonisolated enum AXWindowListRetryPolicy {
    static func persistsUnavailablePID(after _: AXWindowListFailureKind) -> Bool {
        false
    }
}

nonisolated enum SwitcherCommitPolicy {
    enum Action: Equatable {
        case activate
        case waitForSession
        case cancel
    }

    static func action(hasSelectedWindow: Bool, isOpening: Bool) -> Action {
        if hasSelectedWindow { return .activate }
        if isOpening { return .waitForSession }
        return .cancel
    }
}

nonisolated enum WindowRaiseMatching {
    static func matches(
        recordTitle: String,
        recordFrame: CGRect,
        windowTitle: String,
        windowFrame: CGRect
    ) -> Bool {
        let record = recordTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let window = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !record.isEmpty {
            return record == window
        }
        return window.isEmpty
            && abs(recordFrame.minX - windowFrame.minX) < 12
            && abs(recordFrame.minY - windowFrame.minY) < 40
            && abs(recordFrame.width - windowFrame.width) < 24
            && abs(recordFrame.height - windowFrame.height) < 48
    }

    static func score(
        recordTitle: String,
        recordFrame: CGRect,
        windowTitle: String,
        windowFrame: CGRect
    ) -> Int {
        if matches(
            recordTitle: recordTitle,
            recordFrame: recordFrame,
            windowTitle: windowTitle,
            windowFrame: windowFrame
        ) {
            return 1000
        }
        let titleScore = WindowMenuRaiseMatching.score(
            recordTitle: recordTitle,
            menuItemTitle: windowTitle
        )
        guard titleScore > 0 else { return 0 }
        return titleScore + (isNear(recordFrame, windowFrame) ? 20 : 0)
    }

    private static func isNear(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) < 12
            && abs(lhs.minY - rhs.minY) < 40
            && abs(lhs.width - rhs.width) < 24
            && abs(lhs.height - rhs.height) < 48
    }
}

nonisolated enum WindowFrontVerification {
    static func isFront(targetID: CGWindowID?, frontmostIDForProcess: CGWindowID?) -> Bool {
        guard let targetID, let frontmostIDForProcess else { return false }
        return targetID == frontmostIDForProcess
    }
}

nonisolated enum WindowMenuRaiseMatching {
    static let minimumPrefixLength = 8

    static func score(recordTitle: String, menuItemTitle: String) -> Int {
        let record = normalize(recordTitle)
        let item = normalize(menuItemTitle)
        guard !record.isEmpty, !item.isEmpty else { return 0 }
        if record == item { return 100 + item.count }
        if item.count >= minimumPrefixLength, record.hasPrefix(item) { return 50 + item.count }
        if record.count >= minimumPrefixLength, item.hasPrefix(record) { return 40 + record.count }
        return 0
    }

    static func normalize(_ title: String) -> String {
        var value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let numbered = value.range(of: #"^\d+[\.\:\)]\s+"#, options: .regularExpression) {
            value.removeSubrange(numbered)
        } else if let numbered = value.range(of: #"^\d+\s+"#, options: .regularExpression) {
            value.removeSubrange(numbered)
        }
        return value
    }
}
