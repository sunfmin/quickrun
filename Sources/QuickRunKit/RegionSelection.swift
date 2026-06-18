import CoreGraphics
import Foundation

/// The Capture region the user drags out on the frozen Editor overlay, expressed
/// in the overlay's point space — the frozen display's bounds, origin at its
/// bottom-left corner (AppKit convention).
///
/// Pure geometry: the drag-to-rectangle math, normalization, and clamping live
/// here so they are unit-tested without a window or ScreenCaptureKit. The resize
/// and move handles are added in a later slice. The owning overlay maps view
/// points to image pixels itself, since only it knows the Retina scale.
public struct RegionSelection: Equatable {
    /// The selected rectangle: always normalized (non-negative size) and clamped
    /// to `bounds`.
    public private(set) var rect: CGRect

    /// The frozen display's bounds the region is confined to.
    public let bounds: CGRect

    /// Drags shorter than this in either axis are not a deliberate Capture — the
    /// overlay treats them as a cancel rather than a sliver of a region.
    public static let minSize: CGFloat = 8

    public init(bounds: CGRect, rect: CGRect = .zero) {
        self.bounds = bounds.standardized
        self.rect = Self.clamp(rect.standardized, to: self.bounds)
    }

    /// Build a region from a drag between two corners in any direction. The
    /// rectangle is normalized to a non-negative size and clamped to `bounds`, so
    /// dragging up-left yields the same region as dragging down-right.
    public static func fromDrag(from start: CGPoint, to end: CGPoint, in bounds: CGRect) -> RegionSelection {
        let box = bounds.standardized
        let a = clampPoint(start, to: box)
        let b = clampPoint(end, to: box)
        let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                          width: abs(b.x - a.x), height: abs(b.y - a.y))
        return RegionSelection(bounds: box, rect: rect)
    }

    /// True when the region is too small in either axis to be a deliberate
    /// Capture (a click or a tiny twitch rather than a drag).
    public var isEmpty: Bool {
        rect.width < Self.minSize || rect.height < Self.minSize
    }

    // MARK: - Clamping

    /// Confine `rect` to `bounds` by intersection, falling back to an empty rect
    /// pinned at the drag's corner when the two don't overlap at all.
    static func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        let clipped = rect.intersection(bounds)
        return clipped.isNull ? CGRect(origin: clampPoint(rect.origin, to: bounds), size: .zero) : clipped
    }

    static func clampPoint(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX),
                y: min(max(point.y, bounds.minY), bounds.maxY))
    }
}
