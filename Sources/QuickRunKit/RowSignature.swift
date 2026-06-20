import CoreGraphics
import Foundation

/// Turns a captured frame into the per-row descriptors `ScrollStitcher` compares.
/// Each row becomes a small vector of **block averages** — the row split into a
/// fixed number of horizontal blocks, each reduced to its average byte value.
/// Pure CoreGraphics — no AppKit or ScreenCaptureKit — so it is unit-testable
/// with a synthetic `CGImage`.
///
/// Block averaging (rather than a per-row hash) is what makes overlap detection
/// survive real scrolling: a subpixel vertical shift blends adjacent rows and a
/// hash of the raw bytes would change completely, but the block averages move
/// only slightly, so `ScrollStitcher.rowsMatch` still recognises the row within
/// tolerance.
public enum RowSignature {
    /// One descriptor per pixel row of `image`, top to bottom — `blocks` average
    /// byte values across the row. Returns `[]` if the pixel data can't be read.
    public static func descriptors(of image: CGImage, blocks: Int = 16) -> [[UInt8]] {
        guard let data = image.dataProvider?.data,
              let pointer = CFDataGetBytePtr(data) else { return [] }
        let length = CFDataGetLength(data)
        let bytesPerRow = image.bytesPerRow
        let height = image.height
        // Average only the meaningful bytes of each row, not any trailing padding.
        let bytesPerPixel = max(1, image.bitsPerPixel / 8)
        let rowBytes = min(bytesPerRow, image.width * bytesPerPixel)
        let blockCount = max(1, blocks)

        var result = [[UInt8]]()
        result.reserveCapacity(height)
        for y in 0..<height {
            let base = y * bytesPerRow
            guard base + rowBytes <= length else { break }
            var descriptor = [UInt8](repeating: 0, count: blockCount)
            for block in 0..<blockCount {
                let start = block * rowBytes / blockCount
                let end = (block + 1) * rowBytes / blockCount
                guard end > start else { continue }
                var sum = 0
                for x in start..<end { sum += Int(pointer[base + x]) }
                descriptor[block] = UInt8(sum / (end - start))
            }
            result.append(descriptor)
        }
        return result
    }
}
