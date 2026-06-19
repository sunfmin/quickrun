import Foundation

/// The pure core of scroll capture (ADR 0004): given the consecutive frames of a
/// scrolling region as **row signatures** — one hash per pixel row, top to
/// bottom — it finds how much each frame overlaps the one before and where each
/// frame's top sits in the assembled tall image. It never touches raw pixels or
/// ScreenCaptureKit, so it is testable with synthetic arrays.
///
/// Direction: the user scrolls down, so new content enters at the bottom. Between
/// an earlier frame `a` and a later frame `b`, the rows still on screen are `a`'s
/// bottom rows, which are `b`'s top rows — so the overlap is the longest suffix
/// of `a` equal to a prefix of `b`.
public enum ScrollStitcher {
    /// How many rows the later frame `b` shares with the earlier frame `a`: the
    /// length of the longest suffix of `a` that equals a prefix of `b`. `0` when
    /// nothing matches; the full count when the frames are identical (no scroll).
    ///
    /// Takes the *largest* such overlap — the standard greedy match. Repeated
    /// rows (sticky headers/footers) can in principle yield a false match; that
    /// robustness risk is owned by the driver (ADR 0004), not solved here.
    public static func verticalOverlap(between a: [UInt64], _ b: [UInt64]) -> Int {
        var overlap = min(a.count, b.count)
        while overlap > 0 {
            let aStart = a.count - overlap
            var matched = true
            for i in 0..<overlap where a[aStart + i] != b[i] {
                matched = false
                break
            }
            if matched { return overlap }
            overlap -= 1
        }
        return 0
    }

    /// The top y-offset (in rows) of each frame once stacked with overlaps
    /// removed: the first frame at 0, each next shifted down by the previous
    /// frame's non-overlapping height. The app composites the real CGImages at
    /// these offsets to build the tall Capture.
    public static func offsets(forFrames frames: [[UInt64]]) -> [Int] {
        guard !frames.isEmpty else { return [] }
        var offsets = [0]
        for i in 1..<frames.count {
            let overlap = verticalOverlap(between: frames[i - 1], frames[i])
            offsets.append(offsets[i - 1] + (frames[i - 1].count - overlap))
        }
        return offsets
    }

    /// Total height (in rows) of the stitched image for `frames`.
    public static func stitchedHeight(forFrames frames: [[UInt64]]) -> Int {
        guard let last = frames.last, let lastOffset = offsets(forFrames: frames).last else { return 0 }
        return lastOffset + last.count
    }

    /// Whether the latest frame `b` added nothing new over `a` — the overlap is
    /// the whole frame, so scrolling has reached the end.
    public static func reachedEnd(_ a: [UInt64], _ b: [UInt64]) -> Bool {
        !a.isEmpty && a.count == b.count && verticalOverlap(between: a, b) == a.count
    }
}
