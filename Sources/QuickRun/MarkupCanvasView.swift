import AppKit
import QuickRunKit

/// Displays a Capture and the Markup over it, and turns mouse drags into Markup
/// edits. It owns no model state of its own beyond the in-progress drag: the
/// controller pushes `objects`/`selectedID`/`tool` in, and the canvas reports
/// committed edits back out through its callbacks (one callback = one undo step).
final class MarkupCanvasView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    var objects: [MarkupObject] = [] { didSet { needsDisplay = true } }
    var selectedID: UUID? { didSet { needsDisplay = true } }
    var tool: MarkupTool = .select

    /// A rectangle was drawn (capture space).
    var onAddRectangle: ((CGRect) -> Void)?
    /// An object was clicked (or empty space, `nil`).
    var onSelect: ((UUID?) -> Void)?
    /// The object `id` was dragged by `offset` (capture space).
    var onMove: ((UUID, CGSize) -> Void)?

    // In-progress drag state.
    private var dragStart: CGPoint?
    private var pendingRect: CGRect?
    private var movingID: UUID?
    private var moveOffset: CGSize = .zero

    override var isFlipped: Bool { false } // capture space is bottom-left, like AppKit

    // MARK: - Capture <-> view mapping

    private var imageRect: CGRect {
        guard let image, image.size.width > 0, image.size.height > 0 else { return bounds }
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return CGRect(x: (bounds.width - size.width) / 2,
                      y: (bounds.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    private var scale: CGFloat {
        guard let image, image.size.width > 0 else { return 1 }
        return imageRect.width / image.size.width
    }

    private func toCapture(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - imageRect.minX) / scale, y: (point.y - imageRect.minY) / scale)
    }

    private func toView(_ rect: CGRect) -> CGRect {
        CGRect(x: imageRect.minX + rect.minX * scale, y: imageRect.minY + rect.minY * scale,
               width: rect.width * scale, height: rect.height * scale)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }
        image.draw(in: imageRect)

        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: imageRect.minX, yBy: imageRect.minY)
        transform.scale(by: scale)
        transform.concat()
        for object in objects {
            MarkupDrawing.draw(object.id == movingID ? object.translated(by: moveOffset) : object)
        }
        NSGraphicsContext.restoreGraphicsState()

        if let selected = objects.first(where: { $0.id == selectedID }) {
            let shown = selected.id == movingID ? selected.translated(by: moveOffset) : selected
            drawSelectionHandles(around: toView(shown.bounds))
        }
        if let pendingRect {
            drawRubberBand(toView(pendingRect.standardized))
        }
    }

    private func drawSelectionHandles(around rect: CGRect) {
        let outline = NSBezierPath(rect: rect.insetBy(dx: -3, dy: -3))
        outline.lineWidth = 1
        NSColor.selectedControlColor.setStroke()
        outline.setLineDash([4, 3], count: 2, phase: 0)
        outline.stroke()
    }

    private func drawRubberBand(_ rect: CGRect) {
        NSColor(RGBAColor.sealRed).withAlphaComponent(0.9).setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1.5
        path.setLineDash([5, 3], count: 2, phase: 0)
        path.stroke()
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let point = toCapture(convert(event.locationInWindow, from: nil))
        switch tool {
        case .rectangle:
            dragStart = point
            pendingRect = CGRect(origin: point, size: .zero)
        case .select:
            if let hit = objects.last(where: { $0.bounds.contains(point) }) {
                onSelect?(hit.id)
                movingID = hit.id
                dragStart = point
                moveOffset = .zero
            } else {
                onSelect?(nil)
                dragStart = nil
                movingID = nil
            }
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = toCapture(convert(event.locationInWindow, from: nil))
        guard let start = dragStart else { return }
        switch tool {
        case .rectangle:
            pendingRect = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
                                 width: abs(point.x - start.x), height: abs(point.y - start.y))
        case .select where movingID != nil:
            moveOffset = CGSize(width: point.x - start.x, height: point.y - start.y)
        default:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        switch tool {
        case .rectangle:
            if let rect = pendingRect, rect.width > 2, rect.height > 2 {
                onAddRectangle?(rect)
            }
        case .select:
            if let id = movingID, moveOffset != .zero {
                onMove?(id, moveOffset)
            }
        }
        pendingRect = nil
        dragStart = nil
        movingID = nil
        moveOffset = .zero
        needsDisplay = true
    }
}
