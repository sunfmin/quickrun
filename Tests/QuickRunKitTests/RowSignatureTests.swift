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

    func testOneSignaturePerRow() {
        let sigs = RowSignature.rows(of: image(rowGreys: [10, 20, 30]))
        XCTAssertEqual(sigs.count, 3)
    }

    func testIdenticalRowsHashEqual() {
        let sigs = RowSignature.rows(of: image(rowGreys: [42, 42, 99]))
        XCTAssertEqual(sigs[0], sigs[1], "identical rows must hash equal")
        XCTAssertNotEqual(sigs[1], sigs[2], "different rows must hash differently")
    }

    func testSignaturesFeedOverlapDetection() {
        // Two frames sharing their middle band: a scrolled-by-one capture.
        let a = RowSignature.rows(of: image(rowGreys: [1, 2, 3, 4]))
        let b = RowSignature.rows(of: image(rowGreys: [2, 3, 4, 5]))
        XCTAssertEqual(ScrollStitcher.verticalOverlap(between: a, b), 3)
    }
}
