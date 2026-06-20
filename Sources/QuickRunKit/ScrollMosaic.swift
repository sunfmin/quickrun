import Foundation

/// Assembles a tall Scroll Capture from frames as the user scrolls **freely up and
/// down** (ADR 0004). It is a vertical mosaic, not a one-way append: each new frame
/// is aligned against the page captured so far, near where the previous frame sat,
/// and is only allowed to **grow** the page — adding rows off the top or bottom.
/// Frames that fall entirely inside what's already captured are recognised as
/// repeats and dropped, so scrolling back over seen content never duplicates it.
/// The end result is the whole page, however the user wandered to reveal it.
///
/// Pure: it works on **row descriptors** (`[[UInt8]]`, one per pixel row — see
/// `RowSignature`), so it is testable with synthetic arrays. The app keeps the real
/// CGImages in lockstep and composites them at `placements`.
public struct ScrollMosaic {
    /// The descriptor of every row of the page captured so far, top to bottom.
    public private(set) var canvas: [[UInt8]] = []
    /// The top row (in current canvas coordinates) of each accepted frame, in the
    /// order accepted. The app draws frame *i* at `placements[i]`; later frames
    /// draw on top, so the freshest pixels win in any shared band.
    public private(set) var placements: [Int] = []

    private let tolerance: ScrollStitcher.Tolerance
    /// Farthest (in rows) a frame may have moved since the previous grab — bounds
    /// the alignment search around the last known position.
    private let maxShift: Int
    /// Fewest new rows a frame must add (off either end) to be accepted — a still
    /// or jittering page adds nothing and is treated as a repeat.
    private let minAdvance: Int

    /// Where the previous frame aligned, in current canvas coordinates — the anchor
    /// the next frame's search centres on. Updated on every aligned grab (even a
    /// repeat) so the search follows the viewport as the user scrolls.
    private var lastAlignment = 0

    public init(tolerance: ScrollStitcher.Tolerance, maxShift: Int, minAdvance: Int) {
        self.tolerance = tolerance
        self.maxShift = maxShift
        self.minAdvance = minAdvance
    }

    /// Total height of the assembled page in rows.
    public var height: Int { canvas.count }

    /// Offer a frame to the mosaic. Returns `true` if it grew the page (the app
    /// should keep its image and recomposite), `false` if it was a repeat or could
    /// not be aligned (drop it).
    @discardableResult
    public mutating func add(_ frame: [[UInt8]]) -> Bool {
        guard !frame.isEmpty else { return false }
        guard !canvas.isEmpty else {
            canvas = frame
            placements = [0]
            lastAlignment = 0
            return true
        }

        guard let top = bestAlignment(of: frame) else { return false } // too far / no match

        let newTop = min(0, top)
        let newBottom = max(canvas.count, top + frame.count)
        let grew = (newBottom - newTop) - canvas.count
        guard grew >= minAdvance else {
            lastAlignment = top // a repeat — track the viewport, add nothing
            return false
        }

        let shift = -newTop
        let base = top + shift
        var next = [[UInt8]](repeating: [], count: newBottom - newTop)
        for i in 0..<canvas.count { next[shift + i] = canvas[i] }
        for i in 0..<frame.count { next[base + i] = frame[i] } // overwrite shared rows with the freshest
        canvas = next
        for i in 0..<placements.count { placements[i] += shift }
        placements.append(base)
        lastAlignment = base
        return true
    }

    /// The frame's best top-row position (canvas coordinates, may be negative for
    /// content above the current top) searching ±`maxShift` around the last
    /// alignment, or `nil` if nothing within the window matches well enough.
    private func bestAlignment(of frame: [[UInt8]]) -> Int? {
        let h = frame.count
        var best: Int?
        var bestRatio = 0.0
        for top in (lastAlignment - maxShift)...(lastAlignment + maxShift) {
            let overlapStart = max(top, 0)
            let overlapEnd = min(top + h, canvas.count)
            let len = overlapEnd - overlapStart
            guard len >= tolerance.minOverlap else { continue }

            let allowed = Int(Double(len) * (1 - tolerance.minMatchRatio))
            var mismatched = 0
            var matched = true
            for k in 0..<len where !ScrollStitcher.rowsMatch(frame[overlapStart - top + k], canvas[overlapStart + k], tolerance: tolerance.rowTolerance) {
                mismatched += 1
                if mismatched > allowed { matched = false; break }
            }
            guard matched else { continue }

            let ratio = Double(len - mismatched) / Double(len)
            // Best match wins; ties break toward the position nearest the anchor,
            // which keeps a consistent alignment on repetitive content.
            if best == nil || ratio > bestRatio ||
                (ratio == bestRatio && abs(top - lastAlignment) < abs(best! - lastAlignment)) {
                best = top
                bestRatio = ratio
            }
        }
        return best
    }
}
