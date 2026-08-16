import Foundation

enum SwitchDirection: Equatable, Sendable {
    case forward
    case backward
}

enum GridVerticalDirection: Equatable, Sendable {
    case up
    case down
}

struct SwitchSession {
    let windows: [WindowRecord]
    var selectedIndex: Int
    var query: String = ""

    init(windows: [WindowRecord], selectedIndex: Int, query: String = "") {
        self.windows = windows
        self.selectedIndex = selectedIndex
        self.query = query
    }

    var filteredWindows: [WindowRecord] {
        guard !query.isEmpty else { return windows }
        return windows.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.applicationName.localizedCaseInsensitiveContains(query)
                || ($0.bundleIdentifier?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var selectedWindow: WindowRecord? {
        let candidates = filteredWindows
        guard candidates.indices.contains(selectedIndex) else { return candidates.first }
        return candidates[selectedIndex]
    }

    mutating func move(_ direction: SwitchDirection) {
        let count = filteredWindows.count
        guard count > 0 else {
            selectedIndex = 0
            return
        }
        let delta = direction == .forward ? 1 : -1
        selectedIndex = (selectedIndex + delta + count) % count
    }

    mutating func moveVertically(_ direction: GridVerticalDirection, columns: Int) {
        let count = filteredWindows.count
        guard count > 0 else {
            selectedIndex = 0
            return
        }
        let delta = max(columns, 1) * (direction == .down ? 1 : -1)
        let destination = selectedIndex + delta
        guard (0..<count).contains(destination) else { return }
        selectedIndex = destination
    }

    mutating func updateQuery(_ newQuery: String) {
        query = newQuery
        selectedIndex = 0
    }

    mutating func removeSelectedWindow() {
        guard let selected = selectedWindow,
              let sourceIndex = windows.firstIndex(where: { $0.id == selected.id })
        else { return }
        let filtered = filteredWindows
        let filteredIndex = filtered.firstIndex(where: { $0.id == selected.id }) ?? 0
        let nextFilteredID: WindowRecord.ID?
        if filtered.indices.contains(filteredIndex + 1) {
            nextFilteredID = filtered[filteredIndex + 1].id
        } else if filteredIndex > 0 {
            nextFilteredID = filtered[filteredIndex - 1].id
        } else {
            nextFilteredID = nil
        }
        var remaining = windows
        remaining.remove(at: sourceIndex)
        self = SwitchSession(
            windows: remaining,
            selectedIndex: 0,
            query: query
        )
        if let nextFilteredID,
           let index = filteredWindows.firstIndex(where: { $0.id == nextFilteredID }) {
            selectedIndex = index
        } else if !filteredWindows.isEmpty {
            selectedIndex = min(filteredIndex, filteredWindows.count - 1)
        }
    }

}

enum SwitcherListFreeze {
    static func merge(visible: [WindowRecord], refreshed: [WindowRecord]) -> [WindowRecord] {
        var remaining = refreshed
        var merged: [WindowRecord] = []
        for visibleWindow in visible {
            if let index = remaining.firstIndex(where: { $0.id == visibleWindow.id }) {
                merged.append(remaining.remove(at: index))
            } else if let cgWindowID = visibleWindow.cgWindowID,
                      let index = remaining.firstIndex(where: { $0.cgWindowID == cgWindowID }) {
                merged.append(remaining.remove(at: index))
            }
        }
        if merged.isEmpty {
            return refreshed
        }
        return merged
    }
}
