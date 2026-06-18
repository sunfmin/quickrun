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

/// Stroke colour and width shared by Markup objects.
public struct MarkupStyle: Equatable {
    public var stroke: RGBAColor
    public var lineWidth: Double

    public init(stroke: RGBAColor = .sealRed, lineWidth: Double = 3) {
        self.stroke = stroke
        self.lineWidth = lineWidth
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
    }

    public init(id: UUID = UUID(), kind: Kind, style: MarkupStyle = MarkupStyle()) {
        self.id = id
        self.kind = kind
        self.style = style
    }

    /// A copy translated by `offset`, used when dragging an object.
    public func translated(by offset: CGSize) -> MarkupObject {
        var copy = self
        switch kind {
        case .rectangle(let rect):
            copy.kind = .rectangle(rect.offsetBy(dx: offset.width, dy: offset.height))
        }
        return copy
    }

    /// Axis-aligned bounds in capture space, for hit-testing and selection.
    public var bounds: CGRect {
        switch kind {
        case .rectangle(let rect):
            return rect.standardized
        }
    }
}
