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

    // MARK: - Handles (resize / move)

    /// The eight drag points around the region: the four corners and the four
    /// edge midpoints.
    public enum Handle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

        var movesLeft: Bool { self == .topLeft || self == .left || self == .bottomLeft }
        var movesRight: Bool { self == .topRight || self == .right || self == .bottomRight }
        var movesTop: Bool { self == .topLeft || self == .top || self == .topRight }
        var movesBottom: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }
    }

    /// The center of `handle` in bounds space (bottom-left origin), for drawing
    /// the handle and hit-testing it.
    public func handlePoint(_ handle: Handle) -> CGPoint {
        let x = handle.movesLeft ? rect.minX : (handle.movesRight ? rect.maxX : rect.midX)
        let y = handle.movesBottom ? rect.minY : (handle.movesTop ? rect.maxY : rect.midY)
        return CGPoint(x: x, y: y)
    }

    /// The handle within `tolerance` of `point`, preferring the nearest — or
    /// `nil` if the point is on none. Only meaningful for a non-empty region.
    public func handle(at point: CGPoint, tolerance: CGFloat) -> Handle? {
        guard !isEmpty else { return nil }
        var best: (handle: Handle, distance: CGFloat)?
        for handle in Handle.allCases {
            let p = handlePoint(handle)
            let distance = hypot(p.x - point.x, p.y - point.y)
            if distance <= tolerance, best == nil || distance < best!.distance {
                best = (handle, distance)
            }
        }
        return best?.handle
    }

    /// Resize by dragging `handle` to `point`. The moved edges follow the cursor,
    /// clamped to `bounds`, and the region keeps at least `minSize` in each axis
    /// (the dragged edge stops rather than crossing or collapsing).
    public func resized(_ handle: Handle, to point: CGPoint) -> RegionSelection {
        let p = Self.clampPoint(point, to: bounds)
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY

        if handle.movesLeft { minX = min(p.x, maxX - Self.minSize) }
        if handle.movesRight { maxX = max(p.x, minX + Self.minSize) }
        if handle.movesBottom { minY = min(p.y, maxY - Self.minSize) }
        if handle.movesTop { maxY = max(p.y, minY + Self.minSize) }

        let resized = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return RegionSelection(bounds: bounds, rect: resized)
    }

    /// Move the whole region by `offset`, clamped so it cannot leave `bounds`
    /// (the size is preserved — it slides, it does not shrink, at an edge).
    public func moved(by offset: CGSize) -> RegionSelection {
        var moved = rect.offsetBy(dx: offset.width, dy: offset.height)
        moved.origin.x = min(max(moved.minX, bounds.minX), bounds.maxX - moved.width)
        moved.origin.y = min(max(moved.minY, bounds.minY), bounds.maxY - moved.height)
        return RegionSelection(bounds: bounds, rect: moved)
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
