import CoreGraphics
import Foundation

nonisolated struct WindowMatchingCandidate: Equatable, Sendable {
    let id: CGWindowID
    let pid: pid_t
    let title: String
    let frame: CGRect
    let layer: Int
}

nonisolated enum WindowMatcher {
    static func score(
        pid: pid_t,
        title: String,
        frame: CGRect,
        candidate: WindowMatchingCandidate
    ) -> Int {
        guard candidate.pid == pid, candidate.layer == 0 else { return 0 }
        var score = 100
        if candidate.title == title {
            score += 40
        } else if WindowMenuRaiseMatching.score(
            recordTitle: title,
            menuItemTitle: candidate.title
        ) > 0 {
            score += 40
        }
        if abs(candidate.frame.minX - frame.minX) < 12,
           abs(candidate.frame.minY - frame.minY) < 40 {
            score += 30
        }
        if abs(candidate.frame.width - frame.width) < 24,
           abs(candidate.frame.height - frame.height) < 48 {
            score += 30
        }
        return score
    }

    static func bestMatch(
        pid: pid_t,
        title: String,
        frame: CGRect,
        candidates: [WindowMatchingCandidate],
        excluding claimedIDs: Set<CGWindowID> = [],
        preferredWindowID: CGWindowID? = nil,
        threshold: Int = 140
    ) -> WindowMatchingCandidate? {
        let available = claimedIDs.isEmpty
            ? candidates
            : candidates.filter { !claimedIDs.contains($0.id) }
        if let preferredWindowID,
           let preferred = available.first(where: { $0.id == preferredWindowID }) {
            return preferred
        }
        let scored = available.compactMap { candidate -> (WindowMatchingCandidate, Int)? in
            let value = score(pid: pid, title: title, frame: frame, candidate: candidate)
            guard value >= threshold else { return nil }
            return (candidate, value)
        }
        guard let best = scored.max(by: { $0.1 < $1.1 }) else { return nil }
        let tied = scored.contains { $0.0.id != best.0.id && $0.1 == best.1 }
        guard !tied else { return nil }
        return best.0
    }
}

nonisolated enum WindowProcessEnumerator {
    static func pidsToInspect(
        workspacePIDs: Set<pid_t>,
        windowPIDs: Set<pid_t>,
        excluding selfPID: pid_t
    ) -> Set<pid_t> {
        workspacePIDs.union(windowPIDs).subtracting([selfPID])
    }
}

enum WindowZOrder {
    static func ranked(_ windows: [WindowRecord], cgWindowIDsFrontToBack: [CGWindowID]) -> [WindowRecord] {
        let ranks = RecentWindowOrder.combinedRanks(
            primaryIDs: cgWindowIDsFrontToBack,
            secondaryIDs: []
        )
        return windows.enumerated().sorted { lhs, rhs in
            let left = lhs.element.cgWindowID.flatMap { ranks[$0] } ?? Int.max
            let right = rhs.element.cgWindowID.flatMap { ranks[$0] } ?? Int.max
            if left != right { return left < right }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
}

enum WindowUsageOrder {
    static func idsFrontToBack(onScreen: [CGWindowID], remaining: [CGWindowID]) -> [CGWindowID] {
        var seen = Set<CGWindowID>()
        var ordered: [CGWindowID] = []
        for windowID in onScreen + remaining where seen.insert(windowID).inserted {
            ordered.append(windowID)
        }
        return ordered
    }

    static func markedCurrent(
        _ windows: [WindowRecord],
        frontToBackCGWindowIDs: [CGWindowID]
    ) -> [WindowRecord] {
        let includedIDs = Set(windows.compactMap(\.cgWindowID))
        guard let currentID = frontToBackCGWindowIDs.first(where: includedIDs.contains) else {
            return windows
        }
        return windows.map { $0.withCurrentState($0.cgWindowID == currentID) }
    }
}

enum WindowServerList {
    struct OnScreenWindow: Equatable {
        let id: CGWindowID
        let pid: pid_t
        let ownerName: String
    }

    static func onScreenLayer0WindowsFrontToBack() -> [OnScreenWindow] {
        layer0WindowsFrontToBack(onScreenOnly: true)
    }

    static func layer0IDsFrontToBack(onScreenOnly: Bool) -> [CGWindowID] {
        layer0WindowsFrontToBack(onScreenOnly: onScreenOnly).map(\.id)
    }

    static func onScreenLayer0IDsFrontToBack() -> [CGWindowID] {
        layer0IDsFrontToBack(onScreenOnly: true)
    }

    static func frontmostLayer0WindowID(for pid: pid_t) -> CGWindowID? {
        layer0WindowsFrontToBack(onScreenOnly: true).first { $0.pid == pid }?.id
    }

    private static func layer0WindowsFrontToBack(onScreenOnly: Bool) -> [OnScreenWindow] {
        autoreleasepool {
            let options: CGWindowListOption = onScreenOnly
                ? [.optionOnScreenOnly, .excludeDesktopElements]
                : [.optionAll, .excludeDesktopElements]
            guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
                return []
            }
            return raw.compactMap { info in
                let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
                guard layer == 0,
                      let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                      let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
                else { return nil }
                return OnScreenWindow(
                    id: id,
                    pid: pid,
                    ownerName: info[kCGWindowOwnerName as String] as? String ?? ""
                )
            }
        }
    }
}

enum WindowScanTrace {
    static func duplicateCGWindowIDs(in records: [WindowRecord]) -> [CGWindowID] {
        var seen = Set<CGWindowID>()
        var duplicates: [CGWindowID] = []
        for windowID in records.compactMap(\.cgWindowID) {
            if !seen.insert(windowID).inserted, !duplicates.contains(windowID) {
                duplicates.append(windowID)
            }
        }
        return duplicates
    }

    static func onScreenIDs(in records: [WindowRecord], matching liveIDs: [CGWindowID]) -> [CGWindowID] {
        let included = Set(liveIDs)
        return records.compactMap(\.cgWindowID).filter { included.contains($0) }
    }

    static func summary(records: [WindowRecord]) -> String {
        let duplicates = duplicateCGWindowIDs(in: records)
        let missing = records.filter { $0.cgWindowID == nil }.count
        let rows = records.enumerated().map { index, window in
            let mark = window.isCurrent ? "*" : "."
            let cg = window.cgWindowID.map(String.init) ?? "nil"
            return "\(index)\(mark)\(window.applicationName)#\(cg)"
        }.joined(separator: " ")
        var prefix = "count=\(records.count) missingCG=\(missing)"
        if !duplicates.isEmpty {
            prefix += " duplicateCG=\(duplicates.map(String.init).joined(separator: ","))"
        }
        return "\(prefix) \(rows)"
    }

    static func sessionSummary(_ session: SwitchSession) -> String {
        let selected = session.selectedWindow
        let selectedText = selected.map { window in
            "\(window.applicationName)#\(window.cgWindowID.map(String.init) ?? "nil")"
        } ?? "none"
        return "selected=\(session.selectedIndex):\(selectedText) \(summary(records: session.windows))"
    }

    static func liveZOrderSummary(_ windows: [WindowServerList.OnScreenWindow], limit: Int = 12) -> String {
        windows.prefix(limit).enumerated().map { index, window in
            "\(index).\(window.ownerName)#\(window.id)"
        }.joined(separator: " ")
    }
}

enum RecentWindowOrder {
    static func combinedRanks(
        primaryIDs: [CGWindowID],
        secondaryIDs: [CGWindowID]
    ) -> [CGWindowID: Int] {
        var ranks: [CGWindowID: Int] = [:]
        var next = 0
        for windowID in primaryIDs + secondaryIDs where ranks[windowID] == nil {
            ranks[windowID] = next
            next += 1
        }
        return ranks
    }

    static func frontmostCGWindowID(
        for pid: pid_t,
        frontToBackCGWindowIDs: [CGWindowID],
        snapshots: [(id: CGWindowID, pid: pid_t)]
    ) -> CGWindowID? {
        let owned = Set(snapshots.filter { $0.pid == pid }.map(\.id))
        return frontToBackCGWindowIDs.first { owned.contains($0) }
    }
}

nonisolated enum WindowInclusion {
    static func allowsDialog(
        _ isDialog: Bool,
        includesDialogs: Bool,
        belongsToCurrentApplication: Bool
    ) -> Bool {
        !isDialog || includesDialogs || belongsToCurrentApplication
    }

    static func allowsOwnApplicationWindow(isOwnApplication: Bool, windowServerLayer: Int?) -> Bool {
        guard isOwnApplication else { return true }
        return windowServerLayer == 0
    }
}
