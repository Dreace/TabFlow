import CoreGraphics
import XCTest
@testable import TabFlow

final class OverlayPanelSizeCalculatorTests: XCTestCase {
    func testGridUsesFourColumnsAndCapsHeightBeforePresentation() {
        let size = OverlayPanelSizeCalculator.size(
            for: (1...9).map { window(UInt64($0)) },
            layout: .grid,
            cardSize: .medium,
            showsWindowStatus: true,
            groupsApplications: false
        )

        XCTAssertEqual(size.width, 1_024)
        XCTAssertEqual(size.height, 640)
    }

    func testTwoGridRowsFitWithoutScrolling() {
        let size = OverlayPanelSizeCalculator.size(
            for: (1...8).map { window(UInt64($0)) },
            layout: .grid,
            cardSize: .medium,
            showsWindowStatus: true,
            groupsApplications: false
        )

        XCTAssertEqual(size.height, 567)
        XCTAssertLessThan(size.height, 640)
    }

    func testListSizeDoesNotDependOnThumbnailSettings() {
        let windows = (1...5).map { window(UInt64($0)) }
        let first = OverlayPanelSizeCalculator.size(
            for: windows,
            layout: .list,
            cardSize: .small,
            showsWindowStatus: false,
            groupsApplications: false
        )
        let second = OverlayPanelSizeCalculator.size(
            for: windows,
            layout: .list,
            cardSize: .large,
            showsWindowStatus: false,
            groupsApplications: false
        )

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.width, 640)
    }

    func testListSizeGrowsWhenWindowStatusIsShown() {
        let windows = (1...5).map { window(UInt64($0)) }
        let withoutStatus = OverlayPanelSizeCalculator.size(
            for: windows,
            layout: .list,
            cardSize: .medium,
            showsWindowStatus: false,
            groupsApplications: false
        )
        let withStatus = OverlayPanelSizeCalculator.size(
            for: windows,
            layout: .list,
            cardSize: .medium,
            showsWindowStatus: true,
            groupsApplications: false
        )

        XCTAssertEqual(withoutStatus.width, withStatus.width)
        XCTAssertGreaterThan(withStatus.height, withoutStatus.height)
    }

    func testHorizontalLayoutKeepsASingleRowWidth() {
        let size = OverlayPanelSizeCalculator.size(
            for: (1...3).map { window(UInt64($0)) },
            layout: .horizontal,
            cardSize: .medium,
            showsWindowStatus: true,
            groupsApplications: false
        )

        XCTAssertEqual(size.width, 776)
        XCTAssertEqual(size.height, 335)
    }

    func testAutomaticLayoutMatchesHorizontalWhenWindowsFitOneRow() {
        let automatic = OverlayPanelSizeCalculator.size(
            for: (1...3).map { window(UInt64($0)) },
            layout: .automatic,
            cardSize: .medium,
            showsWindowStatus: true,
            groupsApplications: false
        )
        let horizontal = OverlayPanelSizeCalculator.size(
            for: (1...3).map { window(UInt64($0)) },
            layout: .horizontal,
            cardSize: .medium,
            showsWindowStatus: true,
            groupsApplications: false
        )

        XCTAssertEqual(automatic, horizontal)
    }

    func testAutomaticLayoutMatchesGridWhenWindowsNeedMultipleRows() {
        let automatic = OverlayPanelSizeCalculator.size(
            for: (1...9).map { window(UInt64($0)) },
            layout: .automatic,
            cardSize: .medium,
            showsWindowStatus: true,
            groupsApplications: false
        )
        let grid = OverlayPanelSizeCalculator.size(
            for: (1...9).map { window(UInt64($0)) },
            layout: .grid,
            cardSize: .medium,
            showsWindowStatus: true,
            groupsApplications: false
        )

        XCTAssertEqual(automatic, grid)
        XCTAssertEqual(automatic.width, 1_024)
        XCTAssertEqual(automatic.height, 640)
    }

    func testHidingKeyboardHintReducesPanelHeight() {
        let windows = (1...3).map { window(UInt64($0)) }
        let shown = OverlayPanelSizeCalculator.size(
            for: windows,
            layout: .horizontal,
            cardSize: .medium,
            showsWindowStatus: true,
            groupsApplications: false,
            showsKeyboardHint: true
        )
        let hidden = OverlayPanelSizeCalculator.size(
            for: windows,
            layout: .horizontal,
            cardSize: .medium,
            showsWindowStatus: true,
            groupsApplications: false,
            showsKeyboardHint: false
        )

        XCTAssertGreaterThan(shown.height, hidden.height)
    }

    func testThumbnailDisplaySizeFitsAndPreservesAspectRatio() {
        let fitted = DesignTokens.thumbnailDisplaySize(
            for: CGSize(width: 800, height: 400),
            in: CGSize(width: 200, height: 120)
        )
        XCTAssertEqual(fitted.width, 200)
        XCTAssertEqual(fitted.height, 100)
    }

    func testThumbnailCaptureSizeMatchesWindowAspectRatio() {
        let landscape = ThumbnailCaptureSize.pixelSize(
            for: CGSize(width: 1_600, height: 900),
            fitting: CGSize(width: 320, height: 200)
        )
        XCTAssertEqual(landscape.width, 400)
        XCTAssertEqual(landscape.height, 225)

        let portrait = ThumbnailCaptureSize.pixelSize(
            for: CGSize(width: 600, height: 1_200),
            fitting: CGSize(width: 320, height: 200)
        )
        XCTAssertEqual(portrait.width, 200)
        XCTAssertEqual(portrait.height, 400)
        XCTAssertEqual(ThumbnailLoadLimiter.maximumConcurrentCaptures, 3)
        XCTAssertEqual(ThumbnailCaptureSize.maximumPixelDimension, 400)
        XCTAssertEqual(ThumbnailLoadLimiter.maximumCachedThumbnails, 128)
    }

    func testThumbnailRasterizerDownsamplesOversizedCaptures() {
        let captured = makeImage(width: 1_600, height: 900)
        let constrained = ThumbnailRasterizer.constrained(
            captured,
            fitting: CGSize(width: 320, height: 200)
        )
        XCTAssertEqual(constrained.width, 400)
        XCTAssertEqual(constrained.height, 225)
    }

    func testGroupedWindowsReserveSpaceForEachSectionHeader() {
        let grouped = OverlayPanelSizeCalculator.size(
            for: [window(1, bundle: "com.example.first"), window(2, bundle: "com.example.second")],
            layout: .grid,
            cardSize: .medium,
            showsWindowStatus: true,
            groupsApplications: true
        )
        let ungrouped = OverlayPanelSizeCalculator.size(
            for: [window(1, bundle: "com.example.first"), window(2, bundle: "com.example.second")],
            layout: .grid,
            cardSize: .medium,
            showsWindowStatus: true,
            groupsApplications: false
        )

        XCTAssertGreaterThan(grouped.height, ungrouped.height)
    }

    private func window(_ generation: UInt64, bundle: String = "com.example.application") -> WindowRecord {
        WindowRecord(
            id: .init(pid: 100, generation: generation),
            pid: 100,
            bundleIdentifier: bundle,
            applicationName: "Application",
            applicationIconData: nil,
            title: "Window",
            frame: CGRect(x: 0, y: 0, width: 800, height: 600),
            cgWindowID: CGWindowID(generation),
            isMinimized: false,
            isHidden: false,
            isFullScreen: false,
            isDialog: false,
            isOnScreen: true,
            displayName: "Display",
            isCurrent: false
        )
    }

    private func makeImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        XCTAssertNotNil(context)
        context?.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context?.makeImage()
        XCTAssertNotNil(image)
        return image!
    }
}
