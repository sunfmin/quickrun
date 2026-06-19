import CoreGraphics
import Foundation

/// A device-independent RGBA colour, so the Markup model carries no AppKit.
public struct RGBAColor: Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// The Chinese seal red used across QuickRun's chrome.
    public static let sealRed = RGBAColor(red: 0.84, green: 0.27, blue: 0.24)
}

/// Stroke colour and width shared by Markup objects, plus the type size used by
/// text labels.
public struct MarkupStyle: Equatable {
    public var stroke: RGBAColor
    public var lineWidth: Double
    public var fontSize: Double

    public init(stroke: RGBAColor = .sealRed, lineWidth: Double = 3, fontSize: Double = 28) {
        self.stroke = stroke
        self.lineWidth = lineWidth
        self.fontSize = fontSize
    }
}

/// One editable mark laid over a Capture. Geometry is in capture space (the
/// image's own coordinate system, bottom-left origin), so flattening is a direct
/// draw with no coordinate juggling. New kinds (arrow, text, freehand, blur) are
/// added as cases in later slices.
public struct MarkupObject: Equatable, Identifiable {
    public let id: UUID
    public var kind: Kind
    public var style: MarkupStyle

    public enum Kind: Equatable {
        case rectangle(CGRect)
        /// An ellipse inscribed in its bounding rect — circles a region the way
        /// `rectangle` boxes one. Mirrors rectangle in every model respect.
        case ellipse(CGRect)
        case arrow(from: CGPoint, to: CGPoint)
        /// A text label and its frame in capture space (the glue measures the frame).
        case text(String, CGRect)
        /// An emoji glyph stamped at a point, with its frame in capture space.
        /// Mirrors `text` in the model but is placed on click, sized by the
        /// style's font size, and ignores the stroke colour.
        case emoji(String, CGRect)
        case freehand([CGPoint])
        case highlight([CGPoint])
        /// A region whose underlying pixels are pixelated when the Capture is
        /// flattened — redaction, destructive in the output.
        case blur(CGRect)
    }

    public init(id: UUID = UUID(), kind: Kind, style: MarkupStyle = MarkupStyle()) {
        self.id = id
        self.kind = kind
        self.style = style
    }

    /// A copy translated by `offset`, used when dragging an object.
    public func translated(by offset: CGSize) -> MarkupObject {
        let dx = offset.width, dy = offset.height
        var copy = self
        switch kind {
        case .rectangle(let rect):
            copy.kind = .rectangle(rect.offsetBy(dx: dx, dy: dy))
        case .ellipse(let rect):
            copy.kind = .ellipse(rect.offsetBy(dx: dx, dy: dy))
        case .arrow(let from, let to):
            copy.kind = .arrow(from: CGPoint(x: from.x + dx, y: from.y + dy),
                               to: CGPoint(x: to.x + dx, y: to.y + dy))
        case .text(let string, let rect):
            copy.kind = .text(string, rect.offsetBy(dx: dx, dy: dy))
        case .emoji(let string, let rect):
            copy.kind = .emoji(string, rect.offsetBy(dx: dx, dy: dy))
        case .freehand(let points):
            copy.kind = .freehand(points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) })
        case .highlight(let points):
            copy.kind = .highlight(points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) })
        case .blur(let rect):
            copy.kind = .blur(rect.offsetBy(dx: dx, dy: dy))
        }
        return copy
    }

    /// Axis-aligned bounds in capture space, for hit-testing and selection.
    /// Stroked kinds are outset by half the line width so thin marks stay easy
    /// to click.
    public var bounds: CGRect {
        let pad = CGFloat(style.lineWidth) / 2
        switch kind {
        case .rectangle(let rect), .ellipse(let rect):
            return rect.standardized.insetBy(dx: -pad, dy: -pad)
        case .arrow(let from, let to):
            return Self.boundingBox([from, to]).insetBy(dx: -pad, dy: -pad)
        case .text(_, let rect), .emoji(_, let rect):
            return rect.standardized
        case .freehand(let points), .highlight(let points):
            return Self.boundingBox(points).insetBy(dx: -pad, dy: -pad)
        case .blur(let rect):
            return rect.standardized
        }
    }

    private static func boundingBox(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x); maxX = max(maxX, point.x)
            minY = min(minY, point.y); maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
