import CoreGraphics
import Foundation

/// Turns a captured frame into the per-row hashes `ScrollStitcher` compares.
/// Pure CoreGraphics — no AppKit or ScreenCaptureKit — so it is unit-testable
/// with a synthetic `CGImage`.
public enum RowSignature {
    /// One FNV-1a hash per pixel row of `image`, top to bottom. Identical rows
    /// hash equal (so an unchanged band across two frames is detected as
    /// overlap); rows that differ in any byte hash differently. Returns `[]` if
    /// the pixel data can't be read.
    public static func rows(of image: CGImage) -> [UInt64] {
        guard let data = image.dataProvider?.data,
              let pointer = CFDataGetBytePtr(data) else { return [] }
        let length = CFDataGetLength(data)
        let bytesPerRow = image.bytesPerRow
        let height = image.height
        // Hash only the meaningful bytes of each row, not any trailing padding.
        let bytesPerPixel = max(1, image.bitsPerPixel / 8)
        let rowBytes = min(bytesPerRow, image.width * bytesPerPixel)

        var result = [UInt64]()
        result.reserveCapacity(height)
        for y in 0..<height {
            let base = y * bytesPerRow
            guard base + rowBytes <= length else { break }
            var hash: UInt64 = 1469598103934665603 // FNV-1a offset basis
            for x in 0..<rowBytes {
                hash = (hash ^ UInt64(pointer[base + x])) &* 1099511628211
            }
            result.append(hash)
        }
        return result
    }
}
