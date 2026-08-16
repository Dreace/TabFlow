import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class OverlayViewModel {
    var session = SwitchSession(windows: [], selectedIndex: 0)
    var settings: AppSettings?
    var panelSize = OverlayPanelSizeCalculator.defaultSize
    var thumbnails: [WindowRecord.ID: CGImage] = [:]
    var message: String?
    var showsNoWindowsActions = false
    var showsActivationFailureActions = false
    var resolvedLayout: OverlayPresentationLayout = .grid
    var presentationScreenWidth: CGFloat = 1_440
    var onSelect: ((WindowRecord.ID) -> Void)?
    var onRescan: (() -> Void)?
    var onOpenWindowScope: (() -> Void)?
    var onRetryActivation: (() -> Void)?
    var onRemoveFailedWindow: (() -> Void)?
    var onOpenPermissions: (() -> Void)?
    var onQueryChange: ((String) -> Void)?
    var onCancel: (() -> Void)?

    func update(session: SwitchSession, settings: AppSettings) {
        self.session = session
        self.settings = settings
        resolvedLayout = OverlayLayoutResolver.resolve(
            settings.overlayLayout,
            windowCount: session.filteredWindows.count,
            cardSize: settings.cardSize,
            screenWidth: presentationScreenWidth
        )
        message = nil
        showsNoWindowsActions = false
        showsActivationFailureActions = false
    }

    func prepareForPresentation(
        session: SwitchSession,
        settings: AppSettings,
        fixedPanelSize: CGSize? = nil,
        screenWidth: CGFloat = 1_440
    ) {
        presentationScreenWidth = screenWidth
        update(session: session, settings: settings)
        panelSize = fixedPanelSize ?? OverlayPanelSizeCalculator.size(
            for: session.windows,
            layout: settings.overlayLayout,
            cardSize: settings.cardSize,
            showsWindowStatus: settings.showsWindowStatus,
            groupsApplications: settings.groupsApplications,
            screenWidth: screenWidth,
            showsKeyboardHint: settings.showsKeyboardHint
        )
    }

    func prepareNoWindowsPresentation() {
        panelSize = OverlayPanelSizeCalculator.emptyStateSize
    }
}

@MainActor
enum OverlayPanelSizeCalculator {
    static let defaultSize = CGSize(width: 640, height: 320)
    static let emptyStateSize = CGSize(width: 560, height: 380)

    private static let panelPadding: CGFloat = 24
    private static let keyboardHintHeight: CGFloat = 15
    private static let gridHeaderHeight: CGFloat = 21
    private static let listHeaderHeight: CGFloat = 16
    private static let listRowHeight: CGFloat = 44
    private static let listRowHeightWithStatus: CGFloat = 64
    private static let gridMaximumHeight: CGFloat = 640
    private static let listMaximumHeight: CGFloat = 568
    private static let minimumHeight: CGFloat = 300

    static func size(
        for windows: [WindowRecord],
        layout: OverlayLayout,
        cardSize: CardSize,
        showsWindowStatus: Bool,
        groupsApplications: Bool,
        screenWidth: CGFloat = 1_440,
        showsKeyboardHint: Bool = true
    ) -> CGSize {
        switch OverlayLayoutResolver.resolve(
            layout,
            windowCount: windows.count,
            cardSize: cardSize,
            screenWidth: screenWidth
        ) {
        case .grid:
            gridSize(
                windows: windows,
                cardSize: cardSize,
                showsWindowStatus: showsWindowStatus,
                groupsApplications: groupsApplications,
                showsKeyboardHint: showsKeyboardHint
            )
        case .horizontal:
            horizontalSize(
                windows: windows,
                cardSize: cardSize,
                showsWindowStatus: showsWindowStatus,
                screenWidth: screenWidth,
                showsKeyboardHint: showsKeyboardHint
            )
        case .list:
            listSize(
                windows: windows,
                groupsApplications: groupsApplications,
                showsWindowStatus: showsWindowStatus,
                showsKeyboardHint: showsKeyboardHint
            )
        }
    }

    private static func gridSize(
        windows: [WindowRecord],
        cardSize: CardSize,
        showsWindowStatus: Bool,
        groupsApplications: Bool,
        showsKeyboardHint: Bool
    ) -> CGSize {
        let cardWidth = min(DesignTokens.cardWidth(for: cardSize), 240)
        let columnCount = min(max(windows.count, 1), 4)
        let width = CGFloat(columnCount) * cardWidth
            + CGFloat(max(columnCount - 1, 0)) * DesignTokens.spacing
            + panelPadding * 2
        let cardHeight = DesignTokens.thumbnailHeight(for: cardSize)
            + (showsWindowStatus ? 76 : 54)
        let contentHeight = sectionCounts(for: windows, groupsApplications: groupsApplications)
            .enumerated()
            .reduce(CGFloat(8)) { height, item in
                let (sectionIndex, windowCount) = item
                let rows = Int(ceil(Double(windowCount) / Double(columnCount)))
                let rowsHeight = CGFloat(rows) * cardHeight
                    + CGFloat(max(rows - 1, 0)) * DesignTokens.spacing
                let headerHeight = groupsApplications
                    ? gridHeaderHeight + DesignTokens.spacing
                    : 0
                let interSectionSpacing = sectionIndex == 0 ? 0 : DesignTokens.spacing
                return height + headerHeight + interSectionSpacing + rowsHeight
            }
        return CGSize(
            width: width,
            height: boundedHeight(contentHeight + verticalChromeHeight(showsKeyboardHint: showsKeyboardHint), maximum: gridMaximumHeight)
        )
    }

    private static func horizontalSize(
        windows: [WindowRecord],
        cardSize: CardSize,
        showsWindowStatus: Bool,
        screenWidth: CGFloat,
        showsKeyboardHint: Bool
    ) -> CGSize {
        let cardWidth = min(DesignTokens.cardWidth(for: cardSize), 240)
        let columnCount = max(windows.count, 1)
        let contentWidth = CGFloat(columnCount) * cardWidth
            + CGFloat(max(columnCount - 1, 0)) * DesignTokens.spacing
            + panelPadding * 2
        let cardHeight = DesignTokens.thumbnailHeight(for: cardSize)
            + (showsWindowStatus ? 76 : 54)
        return CGSize(
            width: min(max(contentWidth, 320), max(screenWidth - 48, 320)),
            height: boundedHeight(cardHeight + verticalChromeHeight(showsKeyboardHint: showsKeyboardHint), maximum: gridMaximumHeight)
        )
    }

    private static func listSize(
        windows: [WindowRecord],
        groupsApplications: Bool,
        showsWindowStatus: Bool,
        showsKeyboardHint: Bool
    ) -> CGSize {
        let rowHeight = showsWindowStatus ? listRowHeightWithStatus : listRowHeight
        let contentHeight = sectionCounts(for: windows, groupsApplications: groupsApplications)
            .enumerated()
            .reduce(CGFloat(8)) { height, item in
                let (sectionIndex, windowCount) = item
                let rowsHeight = CGFloat(windowCount) * rowHeight
                    + CGFloat(max(windowCount - 1, 0)) * DesignTokens.compactSpacing
                let headerHeight = groupsApplications
                    ? listHeaderHeight + DesignTokens.compactSpacing
                    : 0
                let interSectionSpacing = sectionIndex == 0 ? 0 : DesignTokens.compactSpacing
                return height + headerHeight + interSectionSpacing + rowsHeight
            }
        return CGSize(
            width: 640,
            height: boundedHeight(contentHeight + verticalChromeHeight(showsKeyboardHint: showsKeyboardHint), maximum: listMaximumHeight)
        )
    }

    private static func verticalChromeHeight(showsKeyboardHint: Bool) -> CGFloat {
        panelPadding * 2 + DesignTokens.spacing * 2
            + (showsKeyboardHint ? keyboardHintHeight : 0)
            + searchAreaHeight
    }

    private static let searchAreaHeight: CGFloat = 32

    private static func boundedHeight(_ height: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(height, minimumHeight), maximum)
    }

    private static func sectionCounts(for windows: [WindowRecord], groupsApplications: Bool) -> [Int] {
        guard groupsApplications else { return [max(windows.count, 1)] }

        var counts: [String: Int] = [:]
        var orderedKeys: [String] = []
        for window in windows {
            let key = window.bundleIdentifier ?? "pid:\(window.pid)"
            if counts[key] == nil {
                orderedKeys.append(key)
            }
            counts[key, default: 0] += 1
        }
        return orderedKeys.compactMap { counts[$0] }
    }
}
