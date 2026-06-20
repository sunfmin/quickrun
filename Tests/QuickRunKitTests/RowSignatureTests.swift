import XCTest
import CoreGraphics
@testable import QuickRunKit

final class RowSignatureTests: XCTestCase {
    /// Build a small RGBA image whose rows have the given grey levels (one byte
    /// value per row, repeated across the row), top row first.
    private func image(rowGreys: [UInt8], width: Int = 4) -> CGImage {
        let height = rowGreys.count
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        for y in 0..<height {
            for x in 0..<(width * 4) { bytes[y * bytesPerRow + x] = rowGreys[y] }
        }
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: bytesPerRow, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    func testOneDescriptorPerRow() {
        let descriptors = RowSignature.descriptors(of: image(rowGreys: [10, 20, 30]))
        XCTAssertEqual(descriptors.count, 3)
    }

    func testDescriptorBlockCountIsRequested() {
        let descriptors = RowSignature.descriptors(of: image(rowGreys: [10], width: 8), blocks: 4)
        XCTAssertEqual(descriptors.first?.count, 4)
    }

    func testConstantRowAveragesToThatGrey() {
        // Every block of a constant-grey row averages to the grey.
        let descriptors = RowSignature.descriptors(of: image(rowGreys: [42]), blocks: 8)
        XCTAssertEqual(descriptors.first, [UInt8](repeating: 42, count: 8))
    }

    func testIdenticalRowsDescribeEqual() {
        let descriptors = RowSignature.descriptors(of: image(rowGreys: [42, 42, 99]))
        XCTAssertEqual(descriptors[0], descriptors[1], "identical rows must describe equal")
        XCTAssertNotEqual(descriptors[1], descriptors[2], "different rows must describe differently")
    }

    func testDescriptorsFeedTheMosaic() {
        // Two frames sharing their top/bottom band stitch into one continuous page.
        var mosaic = ScrollMosaic(tolerance: .exact, maxShift: 100, minAdvance: 1)
        XCTAssertTrue(mosaic.add(RowSignature.descriptors(of: image(rowGreys: [1, 2, 3, 4]))))
        XCTAssertTrue(mosaic.add(RowSignature.descriptors(of: image(rowGreys: [2, 3, 4, 5]))))
        XCTAssertEqual(mosaic.height, 5) // [1,2,3,4] + one new row
    }
}
