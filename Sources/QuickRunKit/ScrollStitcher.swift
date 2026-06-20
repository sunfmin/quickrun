import Foundation

/// Row-level matching for scroll capture (ADR 0004). The assembly itself lives in
/// `ScrollMosaic`; this is the shared primitive it builds on: how to decide two
/// pixel rows are "the same".
///
/// The match is **tolerant**, not byte-exact. Real scrolled frames never reproduce
/// a row byte-for-byte — subpixel/Retina resampling and compositor noise perturb
/// every row — so an exact comparison would find almost no overlap and the page
/// could never be aligned. Rows are compared by their block-averaged descriptors
/// (see `RowSignature`) within a tolerance.
public enum ScrollStitcher {
    /// How forgiving matching is.
    public struct Tolerance: Equatable {
        /// Largest total absolute difference between two row descriptors (summed
        /// over their blocks) for the rows to count as the same.
        public let rowTolerance: Int
        /// Fraction of a candidate band's rows that must match for the band to be
        /// accepted as an alignment.
        public let minMatchRatio: Double
        /// Smallest overlapping band considered a real alignment — guards against
        /// accepting a tiny coincidental match.
        public let minOverlap: Int

        public init(rowTolerance: Int, minMatchRatio: Double, minOverlap: Int) {
            self.rowTolerance = rowTolerance
            self.minMatchRatio = minMatchRatio
            self.minOverlap = minOverlap
        }

        /// Byte-exact, any overlap ≥ 1 — used by the synthetic mosaic tests where
        /// rows are single-element descriptors.
        public static let exact = Tolerance(rowTolerance: 0, minMatchRatio: 1, minOverlap: 1)
    }

    /// Whether two row descriptors are the same within `tolerance` (total absolute
    /// difference across their blocks). Differing lengths never match.
    public static func rowsMatch(_ x: [UInt8], _ y: [UInt8], tolerance: Int) -> Bool {
        guard x.count == y.count else { return false }
        var diff = 0
        for i in 0..<x.count {
            diff += abs(Int(x[i]) - Int(y[i]))
            if diff > tolerance { return false }
        }
        return true
    }
}
