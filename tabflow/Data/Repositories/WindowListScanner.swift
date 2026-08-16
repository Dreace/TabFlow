import ApplicationServices
import CoreGraphics
import Foundation
import OSLog

struct ApplicationSnapshot: Sendable {
    let pid: pid_t
    let bundleIdentifier: String?
    let name: String
    let iconData: Data?
    let isHidden: Bool

    var iconCacheKey: String {
        bundleIdentifier ?? "pid:\(pid)"
    }
}

struct CGWindowSnapshot: Sendable {
    let id: CGWindowID
    let pid: pid_t
    let title: String
    let frame: CGRect
    let isOnScreen: Bool
    let alpha: CGFloat
    let layer: Int
}

struct ScreenSnapshot: Sendable {
    let frame: CGRect
    let localizedName: String
    let isMain: Bool
}

struct ScannedAccessibleWindow: @unchecked Sendable {
    let element: AXUIElement?
    let record: WindowRecord
}

struct AXGenerationState: @unchecked Sendable {
    var generations: [pid_t: [(element: AXUIElement, generation: UInt64)]]
    var nextGeneration: UInt64

    mutating func generation(for element: AXUIElement, pid: pid_t) -> UInt64 {
        if let existing = generations[pid]?.first(where: { CFEqual($0.element, element) }) {
            return existing.generation
        }
        let generation = nextGeneration
        nextGeneration += 1
        generations[pid, default: []].append((element, generation))
        return generation
    }
}

struct WindowListScanResult: @unchecked Sendable {
    let windows: [ScannedAccessibleWindow]
    let generationState: AXGenerationState
}

nonisolated enum WindowListScanner {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "tabflow",
        category: "window-scan"
    )

    static func scan(
        applications: [ApplicationSnapshot],
        cgWindows: [CGWindowSnapshot],
        screens: [ScreenSnapshot],
        options: WindowQueryOptions,
        frontmostPID: pid_t?,
        selfPID: pid_t,
        generationState: AXGenerationState
    ) -> WindowListScanResult {
        var generationState = generationState
        var discovered: [ScannedAccessibleWindow] = []
        for application in applications {
            guard !options.ignoredBundleIdentifiers.contains(application.bundleIdentifier ?? ""),
                  options.includesHiddenApplications || !application.isHidden
            else { continue }
            discovered.append(contentsOf: scan(
                application: application,
                cgWindows: cgWindows,
                screens: screens,
                options: options,
                frontmostPID: frontmostPID,
                selfPID: selfPID,
                generationState: &generationState
            ))
        }
        return WindowListScanResult(windows: discovered, generationState: generationState)
    }

    private static func scan(
        application: ApplicationSnapshot,
        cgWindows: [CGWindowSnapshot],
        screens: [ScreenSnapshot],
        options: WindowQueryOptions,
        frontmostPID: pid_t?,
        selfPID: pid_t,
        generationState: inout AXGenerationState
    ) -> [ScannedAccessibleWindow] {
        let applicationElement = AXUIElementCreateApplication(application.pid)
        AXUIElementSetMessagingTimeout(applicationElement, AXScanLimits.messagingTimeout)

        let windows: [AXUIElement]
        do {
            windows = try AXValueReader.windows(from: applicationElement)
        } catch {
            logWindowListFailure(error, application: application)
            return cgFallbackWindows(
                application: application,
                cgWindows: cgWindows,
                screens: screens,
                options: options
            )
        }

        let focusedWindow = try? AXValueReader.element(
            kAXFocusedWindowAttribute as CFString,
            from: applicationElement
        )
        var untitledIndex = 0
        var claimedCGWindowIDs = Set<CGWindowID>()
        var scanned: [ScannedAccessibleWindow] = []

        for element in windows {
            AXUIElementSetMessagingTimeout(element, AXScanLimits.messagingTimeout)
            let attributes = AXValueReader.windowAttributes(from: element)
            let isDialog = attributes.isModal
                || attributes.subrole == kAXDialogSubrole
                || attributes.subrole == kAXSystemDialogSubrole
            let belongsToCurrentApplication = application.pid == frontmostPID
                || application.pid == selfPID
            guard attributes.role == kAXWindowRole,
                  WindowInclusion.allowsDialog(
                    isDialog,
                    includesDialogs: options.includesDialogs,
                    belongsToCurrentApplication: belongsToCurrentApplication
                  )
            else { continue }

            let frame = CGRect(origin: attributes.position, size: attributes.size)
            guard attributes.size.width >= 120, attributes.size.height >= 80 else { continue }

            let accessibilityTitle = attributes.title
            let preferredWindowID = AXWindowIdentity.cgWindowID(from: element)
            let match = bestMatch(
                pid: application.pid,
                title: accessibilityTitle,
                frame: frame,
                candidates: cgWindows,
                excluding: claimedCGWindowIDs,
                preferredWindowID: preferredWindowID
            )
            guard WindowInclusion.allowsOwnApplicationWindow(
                isOwnApplication: application.pid == selfPID,
                windowServerLayer: match?.layer
            ) else { continue }
            guard match?.alpha != 0 else { continue }
            var title = accessibilityTitle.isEmpty
                ? match?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                : accessibilityTitle
            if title.isEmpty {
                guard options.includesUntitledWindows else { continue }
                untitledIndex += 1
                title = String(
                    format: String(localized: "window.fallbackTitle.format"),
                    locale: .current,
                    application.name,
                    untitledIndex
                )
            }

            let generation = generationState.generation(for: element, pid: application.pid)
            let minimized = attributes.isMinimized
            guard options.includesMinimizedWindows || !minimized else { continue }

            let focused = application.pid == frontmostPID
                && (focusedWindow.map { CFEqual($0, element) } ?? attributes.isFocused)
            let fullScreen = attributes.isFullScreen
            let display = display(containing: frame, screens: screens)
            guard WindowSpaceInclusion.allows(
                isOnScreen: match?.isOnScreen ?? false,
                isMinimized: minimized,
                currentSpaceOnly: options.currentSpaceOnly,
                includesMinimizedWindows: options.includesMinimizedWindows
            ) else { continue }

            let cgWindowID = match?.id ?? preferredWindowID.flatMap { claimedCGWindowIDs.contains($0) ? nil : $0 }
            if let cgWindowID {
                claimedCGWindowIDs.insert(cgWindowID)
            }
            let record = WindowRecord(
                id: .init(pid: application.pid, generation: generation),
                pid: application.pid,
                bundleIdentifier: application.bundleIdentifier,
                applicationName: application.name,
                applicationIconData: application.iconData,
                title: title,
                frame: frame,
                cgWindowID: cgWindowID,
                isMinimized: minimized,
                isHidden: application.isHidden,
                isFullScreen: fullScreen,
                isDialog: isDialog,
                isOnScreen: match?.isOnScreen ?? false,
                displayName: display?.localizedName,
                isCurrent: focused
            )
            scanned.append(ScannedAccessibleWindow(element: element, record: record))
        }
        return scanned
    }

    private static func cgFallbackWindows(
        application: ApplicationSnapshot,
        cgWindows: [CGWindowSnapshot],
        screens: [ScreenSnapshot],
        options: WindowQueryOptions
    ) -> [ScannedAccessibleWindow] {
        var untitledIndex = 0
        let fallbacks = cgWindows.compactMap { snapshot -> ScannedAccessibleWindow? in
            guard snapshot.pid == application.pid,
                  snapshot.layer == 0,
                  snapshot.alpha != 0,
                  snapshot.frame.width >= 120,
                  snapshot.frame.height >= 80
            else { return nil }
            let isMinimized = options.currentSpaceOnly && !snapshot.isOnScreen
            if !WindowSpaceInclusion.allows(
                isOnScreen: snapshot.isOnScreen,
                isMinimized: isMinimized,
                currentSpaceOnly: options.currentSpaceOnly,
                includesMinimizedWindows: options.includesMinimizedWindows
            ) { return nil }

            var title = snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty {
                guard options.includesUntitledWindows else { return nil }
                untitledIndex += 1
                title = String(
                    format: String(localized: "window.fallbackTitle.format"),
                    locale: .current,
                    application.name,
                    untitledIndex
                )
            }

            let display = display(containing: snapshot.frame, screens: screens)
            let record = WindowRecord(
                id: .init(pid: application.pid, generation: UInt64(snapshot.id)),
                pid: application.pid,
                bundleIdentifier: application.bundleIdentifier,
                applicationName: application.name,
                applicationIconData: application.iconData,
                title: title,
                frame: snapshot.frame,
                cgWindowID: snapshot.id,
                isMinimized: isMinimized,
                isHidden: application.isHidden,
                isFullScreen: false,
                isDialog: false,
                isOnScreen: snapshot.isOnScreen,
                displayName: display?.localizedName,
                isCurrent: false
            )
            return ScannedAccessibleWindow(element: nil, record: record)
        }
        logger.debug(
            "CG fallback windows pid=\(application.pid, privacy: .public) count=\(fallbacks.count, privacy: .public)"
        )
        return fallbacks
    }

    private static func logWindowListFailure(_ error: Error, application: ApplicationSnapshot) {
        let readError = error as? AXReadError
        let kind = readError?.windowListFailureKind ?? .fatal
        let axName: String
        if case let .failure(_, code) = readError {
            axName = code.diagnosticName
        } else {
            axName = "unknown"
        }
        let message = "AX window list unavailable pid=\(application.pid) bundle=\(application.bundleIdentifier ?? "nil") axError=\(axName) trusted=\(AXIsProcessTrusted()) error=\(String(describing: error)) retryNextScan=\(!AXWindowListRetryPolicy.persistsUnavailablePID(after: kind))"
        switch kind {
        case .transient, .unsupported:
            logger.notice("\(message, privacy: .public)")
        case .fatal:
            logger.error("\(message, privacy: .public)")
        }
    }

    private static func bestMatch(
        pid: pid_t,
        title: String,
        frame: CGRect,
        candidates: [CGWindowSnapshot],
        excluding claimedIDs: Set<CGWindowID>,
        preferredWindowID: CGWindowID?
    ) -> CGWindowSnapshot? {
        let matchingCandidates = candidates.map {
            WindowMatchingCandidate(id: $0.id, pid: $0.pid, title: $0.title, frame: $0.frame, layer: $0.layer)
        }
        guard let matched = WindowMatcher.bestMatch(
            pid: pid,
            title: title,
            frame: frame,
            candidates: matchingCandidates,
            excluding: claimedIDs,
            preferredWindowID: preferredWindowID
        ) else { return nil }
        return candidates.first { $0.id == matched.id }
    }

    private static func display(containing frame: CGRect, screens: [ScreenSnapshot]) -> ScreenSnapshot? {
        screens.max { lhs, rhs in
            DisplayCoordinateSpace.intersectionArea(lhs.frame, frame)
                < DisplayCoordinateSpace.intersectionArea(rhs.frame, frame)
        }
    }
}
