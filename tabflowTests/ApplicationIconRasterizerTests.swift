import AppKit
import XCTest
@testable import TabFlow

final class ApplicationIconRasterizerTests: XCTestCase {
    func testRasterizerEncodesASmallPNGInsteadOfAFullResolutionTIFF() {
        let image = makeLargeIcon()
        let tiff = image.tiffRepresentation
        let png = ApplicationIconRasterizer.pngData(from: image)

        XCTAssertNotNil(tiff)
        XCTAssertNotNil(png)
        XCTAssertGreaterThan(tiff?.count ?? 0, 64 * 1_024)
        XCTAssertLessThan(png?.count ?? .max, 32 * 1_024)
        XCTAssertEqual(png?.prefix(8), Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
    }

    private func makeLargeIcon() -> NSImage {
        let dimension = 1024
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: dimension,
            height: dimension,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: dimension, height: dimension))
        let cgImage = context?.makeImage()
        let image = NSImage(size: NSSize(width: dimension, height: dimension))
        if let cgImage {
            image.addRepresentation(NSBitmapImageRep(cgImage: cgImage))
        }
        return image
    }
}
