import AppKit
import SwiftUI

nonisolated enum OverlayPresentationLayout: Equatable, Sendable {
    case horizontal
    case grid
    case list
}

nonisolated enum AppearancePreviewSample {
    static let thumbnailWidth = 320
    static let thumbnailHeight = 200

    static func resolvedLayout(
        overlayLayout: OverlayLayout,
        cardSize: CardSize
    ) -> OverlayPresentationLayout {
        OverlayLayoutResolver.resolve(
            overlayLayout,
            windowCount: 1,
            cardSize: cardSize,
            screenWidth: 1_440
        )
    }

    static func cardWidth(for cardSize: CardSize) -> CGFloat {
        min(DesignTokens.cardWidth(for: cardSize), 240)
    }

    static func window(
        applicationName: String,
        applicationIconData: Data?,
        title: String
    ) -> WindowRecord {
        WindowRecord(
            id: WindowRecord.ID(pid: 0, generation: 0),
            pid: 0,
            bundleIdentifier: "preview.tabflow",
            applicationName: applicationName,
            applicationIconData: applicationIconData,
            title: title,
            frame: CGRect(x: 80, y: 80, width: 960, height: 640),
            cgWindowID: 1,
            isMinimized: true,
            isHidden: false,
            isFullScreen: false,
            isDialog: false,
            isOnScreen: true,
            displayName: nil,
            isCurrent: false
        )
    }

    static func thumbnailImage() -> CGImage? {
        let width = CGFloat(thumbnailWidth)
        let height = CGFloat(thumbnailHeight)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: thumbnailWidth,
            height: thumbnailHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.setFillColor(CGColor(srgbRed: 0.93, green: 0.94, blue: 0.96, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        context.setFillColor(CGColor(srgbRed: 0.86, green: 0.87, blue: 0.90, alpha: 1))
        context.fill(CGRect(x: 0, y: height - 28, width: width, height: 28))

        func trafficLight(x: CGFloat, red: CGFloat, green: CGFloat, blue: CGFloat) {
            context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
            context.fillEllipse(in: CGRect(x: x, y: height - 20, width: 10, height: 10))
        }
        trafficLight(x: 12, red: 1, green: 0.38, blue: 0.36)
        trafficLight(x: 28, red: 1, green: 0.74, blue: 0.25)
        trafficLight(x: 44, red: 0.19, green: 0.80, blue: 0.40)

        context.setFillColor(CGColor(srgbRed: 0.78, green: 0.81, blue: 0.86, alpha: 1))
        context.fill(CGRect(x: 16, y: 20, width: 88, height: height - 60))
        context.fill(CGRect(x: 116, y: height - 92, width: width - 132, height: 48))
        context.fill(CGRect(x: 116, y: 20, width: width - 132, height: height - 124))
        return context.makeImage()
    }
}

nonisolated enum OverlayLayoutResolver {
    static let maximumGridColumns = 4

    static func resolve(
        _ layout: OverlayLayout,
        windowCount: Int,
        cardSize: CardSize,
        screenWidth: CGFloat
    ) -> OverlayPresentationLayout {
        switch layout {
        case .horizontal:
            return .horizontal
        case .grid:
            return .grid
        case .list:
            return .list
        case .automatic:
            let cardWidth = min(DesignTokens.cardWidth(for: cardSize), 240)
            let availableWidth = max(screenWidth - 48, cardWidth)
            let columnsThatFit = max(
                Int((availableWidth + DesignTokens.spacing) / (cardWidth + DesignTokens.spacing)),
                1
            )
            if windowCount <= min(columnsThatFit, maximumGridColumns) {
                return .horizontal
            }
            return .grid
        }
    }
}

nonisolated enum OverlayAnimationPolicy {
    struct Motion: Equatable {
        let fadesPanel: Bool
        let fadeDuration: TimeInterval
    }

    static func motion(
        preference: AnimationPreference,
        reduceMotion: Bool
    ) -> Motion {
        switch preference {
        case .none:
            return Motion(fadesPanel: false, fadeDuration: 0)
        case .reduced:
            return Motion(fadesPanel: true, fadeDuration: 0.08)
        case .system:
            if reduceMotion {
                return Motion(fadesPanel: false, fadeDuration: 0)
            }
            return Motion(fadesPanel: true, fadeDuration: 0.1)
        }
    }
}

enum OverlayAnimationEnvironment {
    @MainActor
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

nonisolated enum StatusBarIconPolicy {
    static func systemSymbolName(isPaused: Bool) -> String? {
        isPaused ? "pause.circle.fill" : nil
    }
}

nonisolated enum SwitcherEventTapPolicy {
    static func swallowsKeyUp(
        isSwitcherVisible: Bool,
        keyCode: Int64,
        shortcutKeyCode: Int64
    ) -> Bool {
        guard isSwitcherVisible else { return false }
        let consumed: Set<Int64> = [shortcutKeyCode, 36, 51, 53, 76, 123, 124, 125, 126]
        return consumed.contains(keyCode)
    }
}

enum WindowDiagnosticLogging {
    @MainActor
    static var isEnabled = false
}

nonisolated enum WindowSpaceInclusion {
    static func allows(
        isOnScreen: Bool,
        isMinimized: Bool,
        currentSpaceOnly: Bool,
        includesMinimizedWindows: Bool
    ) -> Bool {
        if isMinimized && !includesMinimizedWindows {
            return false
        }
        if isOnScreen {
            return true
        }
        if isMinimized {
            return true
        }
        return !currentSpaceOnly
    }
}

nonisolated enum OverlayDisplayNamePolicy {
    static func showsDisplayName(screenCount: Int) -> Bool {
        screenCount > 1
    }
}

nonisolated enum DisplayCoordinateSpace {
    static func cgFrame(fromAppKitFrame appKitFrame: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(
            x: appKitFrame.minX,
            y: primaryTop - appKitFrame.maxY,
            width: appKitFrame.width,
            height: appKitFrame.height
        )
    }

    static func cgPoint(fromAppKitPoint appKitPoint: CGPoint, primaryTop: CGFloat) -> CGPoint {
        CGPoint(x: appKitPoint.x, y: primaryTop - appKitPoint.y)
    }

    static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, !intersection.isInfinite else { return 0 }
        return intersection.width * intersection.height
    }
}

nonisolated enum WindowRecordSorting {
    static func sorted(_ windows: [WindowRecord], using order: WindowSortOrder) -> [WindowRecord] {
        switch order {
        case .recent:
            windows
        case .application:
            windows.sorted {
                let comparison = $0.applicationName.localizedCaseInsensitiveCompare($1.applicationName)
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        case .title:
            windows.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .display:
            windows.sorted { ($0.displayName ?? "") < ($1.displayName ?? "") }
        }
    }
}

nonisolated enum ThumbnailLoadPlan {
    static let neighborCount = 2

    static func windows(in ordered: [WindowRecord], selectedID: WindowRecord.ID?) -> [WindowRecord] {
        guard let selectedID, let index = ordered.firstIndex(where: { $0.id == selectedID }) else {
            return ordered
        }

        var seen = Set<WindowRecord.ID>()
        var result: [WindowRecord] = []

        func append(_ window: WindowRecord) {
            guard seen.insert(window.id).inserted else { return }
            result.append(window)
        }

        append(ordered[index])
        for offset in 1...neighborCount {
            if index >= offset {
                append(ordered[index - offset])
            }
            if index + offset < ordered.count {
                append(ordered[index + offset])
            }
        }
        for window in ordered {
            append(window)
        }
        return result
    }
}

nonisolated enum ThumbnailCaptureDeduper {
    static func claim(
        _ windows: [WindowRecord],
        started: inout Set<CGWindowID>
    ) -> [WindowRecord] {
        windows.filter { window in
            guard let windowID = window.cgWindowID else { return false }
            return started.insert(windowID).inserted
        }
    }
}

nonisolated enum ThumbnailCacheRetention {
    static func closedWindowIDs(previous: [CGWindowID], current: [CGWindowID]) -> Set<CGWindowID> {
        Set(previous).subtracting(current)
    }
}

nonisolated enum OverlayThumbnailCache {
    static func retained(
        _ images: [CGWindowID: CGImage],
        keeping liveIDs: Set<CGWindowID>
    ) -> [CGWindowID: CGImage] {
        images.filter { liveIDs.contains($0.key) }
    }

    static func fillingGaps(
        existing: [CGWindowID: CGImage],
        remembered: [CGWindowID: CGImage]
    ) -> [CGWindowID: CGImage] {
        var next = existing
        for (windowID, image) in remembered where next[windowID] == nil {
            next[windowID] = image
        }
        return next
    }

    static func capped(
        _ images: [CGWindowID: CGImage],
        preferring preferredIDs: [CGWindowID] = [],
        maximumCount: Int = ThumbnailLoadLimiter.maximumCachedThumbnails,
        maximumBytes: Int = ThumbnailLoadLimiter.maximumCachedBytes
    ) -> [CGWindowID: CGImage] {
        var entries = images.map { (id: $0.key, image: $0.value, bytes: $0.value.bytesPerRow * $0.value.height) }
        let totalBytes = entries.reduce(0) { $0 + $1.bytes }
        guard entries.count > maximumCount || totalBytes > maximumBytes else {
            return images
        }
        let preferred = Set(preferredIDs)
        entries.sort { lhs, rhs in
            let leftPreferred = preferred.contains(lhs.id)
            let rightPreferred = preferred.contains(rhs.id)
            if leftPreferred != rightPreferred {
                return leftPreferred && !rightPreferred
            }
            return lhs.id < rhs.id
        }
        var kept: [CGWindowID: CGImage] = [:]
        var bytes = 0
        for entry in entries {
            if kept.count >= maximumCount { break }
            if bytes + entry.bytes > maximumBytes { continue }
            kept[entry.id] = entry.image
            bytes += entry.bytes
        }
        return kept
    }
}

nonisolated enum ThumbnailImageIndex {
    static func overlayThumbnails(
        windows: [WindowRecord],
        imagesByCGWindowID: [CGWindowID: CGImage]
    ) -> [WindowRecord.ID: CGImage] {
        var result: [WindowRecord.ID: CGImage] = [:]
        for window in windows {
            guard let windowID = window.cgWindowID, let image = imagesByCGWindowID[windowID] else {
                continue
            }
            result[window.id] = image
        }
        return result
    }
}

nonisolated enum CachedWindowFilter {
    static func apply(_ windows: [WindowRecord], options: WindowQueryOptions) -> [WindowRecord] {
        let currentDisplayName = windows.first(where: \.isCurrent)?.displayName
        let filtered = windows.filter { window in
            if let identifier = window.bundleIdentifier,
               options.ignoredBundleIdentifiers.contains(identifier) {
                return false
            }
            if !options.includesHiddenApplications && window.isHidden { return false }
            if !options.includesMinimizedWindows && window.isMinimized { return false }
            if !options.includesUntitledWindows && window.title.isEmpty { return false }
            if !WindowInclusion.allowsDialog(
                window.isDialog,
                includesDialogs: options.includesDialogs,
                belongsToCurrentApplication: window.isCurrent
            ) { return false }
            if !WindowSpaceInclusion.allows(
                isOnScreen: window.isOnScreen,
                isMinimized: window.isMinimized,
                currentSpaceOnly: options.currentSpaceOnly,
                includesMinimizedWindows: options.includesMinimizedWindows
            ) { return false }
            if options.currentDisplayOnly,
               let currentDisplayName,
               window.displayName != currentDisplayName {
                return false
            }
            if !options.includesCurrentWindow && window.isCurrent { return false }
            return true
        }
        return WindowRecordSorting.sorted(filtered, using: options.sortOrder)
    }
}
