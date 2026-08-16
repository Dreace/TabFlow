import CoreGraphics
import Foundation

actor MRUStore {
    private var orderedCGWindowIDs: [CGWindowID] = []
    private var orderedRecordIDs: [WindowRecord.ID] = []

    func recordFocus(_ window: WindowRecord) {
        if let cgWindowID = window.cgWindowID {
            recordFocus(cgWindowID: cgWindowID)
        }
        orderedRecordIDs.removeAll { $0 == window.id }
        orderedRecordIDs.insert(window.id, at: 0)
    }

    func recordFocus(cgWindowID: CGWindowID) {
        orderedCGWindowIDs.removeAll { $0 == cgWindowID }
        orderedCGWindowIDs.insert(cgWindowID, at: 0)
    }

    func order(_ windows: [WindowRecord], frontToBackCGWindowIDs: [CGWindowID] = []) -> [WindowRecord] {
        let cgRanks = RecentWindowOrder.combinedRanks(
            primaryIDs: orderedCGWindowIDs,
            secondaryIDs: frontToBackCGWindowIDs
        )
        let idRanks = Dictionary(
            uniqueKeysWithValues: orderedRecordIDs.enumerated().map { ($0.element, $0.offset) }
        )
        return windows.enumerated().sorted { lhs, rhs in
            let leftRank = rank(lhs.element, cgRanks: cgRanks, idRanks: idRanks)
            let rightRank = rank(rhs.element, cgRanks: cgRanks, idRanks: idRanks)
            if leftRank != rightRank { return leftRank < rightRank }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    func discardMissing(from windows: [WindowRecord]) {
        let validIDs = Set(windows.map(\.id))
        let validCGWindowIDs = Set(windows.compactMap(\.cgWindowID))
        orderedRecordIDs.removeAll { !validIDs.contains($0) }
        orderedCGWindowIDs.removeAll { !validCGWindowIDs.contains($0) }
    }

    private func rank(
        _ window: WindowRecord,
        cgRanks: [CGWindowID: Int],
        idRanks: [WindowRecord.ID: Int]
    ) -> Int {
        if let cgWindowID = window.cgWindowID, let rank = cgRanks[cgWindowID] {
            return rank
        }
        return idRanks[window.id] ?? Int.max
    }
}
