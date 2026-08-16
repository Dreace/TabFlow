import CoreGraphics
import Foundation

nonisolated struct WindowRecord: Identifiable, Hashable, Sendable {
    nonisolated struct ID: Hashable, Sendable {
        let pid: pid_t
        let generation: UInt64
    }

    let id: ID
    let pid: pid_t
    let bundleIdentifier: String?
    let applicationName: String
    let applicationIconData: Data?
    let title: String
    let frame: CGRect
    let cgWindowID: CGWindowID?
    let isMinimized: Bool
    let isHidden: Bool
    let isFullScreen: Bool
    let isDialog: Bool
    let isOnScreen: Bool
    let displayName: String?
    let isCurrent: Bool

    static func == (lhs: WindowRecord, rhs: WindowRecord) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var displayTitle: String {
        title.isEmpty ? String(localized: "window.untitled") : title
    }

    var statusLabels: [String] {
        var labels: [String] = []
        if isMinimized { labels.append(String(localized: "window.status.minimized")) }
        if isHidden { labels.append(String(localized: "window.status.hidden")) }
        if isFullScreen { labels.append(String(localized: "window.status.fullScreen")) }
        if isDialog { labels.append(String(localized: "window.status.dialog")) }
        if cgWindowID == nil { labels.append(String(localized: "window.status.previewUnavailable")) }
        return labels
    }

    func withCurrentState(_ isCurrent: Bool) -> WindowRecord {
        WindowRecord(
            id: id,
            pid: pid,
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName,
            applicationIconData: applicationIconData,
            title: title,
            frame: frame,
            cgWindowID: cgWindowID,
            isMinimized: isMinimized,
            isHidden: isHidden,
            isFullScreen: isFullScreen,
            isDialog: isDialog,
            isOnScreen: isOnScreen,
            displayName: displayName,
            isCurrent: isCurrent
        )
    }
}
