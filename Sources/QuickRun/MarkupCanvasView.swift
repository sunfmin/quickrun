import AppKit
import QuickRunKit

/// Displays a Capture and the Markup over it, and turns mouse drags into Markup
/// edits. It owns no model state beyond the in-progress drag: the controller
/// pushes `objects`/`selectedID`/`tool`/`activeStyle` in, and the canvas reports
/// committed edits back through callbacks (one callback = one undo step).
final class MarkupCanvasView: NSView, NSTextFieldDelegate {
    var image: NSImage? { didSet { needsDisplay = true } }
    var objects: [MarkupObject] = [] { didSet { needsDisplay = true } }
    var selectedID: UUID? { didSet { needsDisplay = true } }
    var tool: MarkupTool = .select
    /// Style used to preview the in-progress mark (the controller applies the
    /// same style when it commits the object).
    var activeStyle = MarkupStyle()

    /// A mark was drawn (capture space). The controller adds it with `activeStyle`.
    var onCommit: ((MarkupObject.Kind) -> Void)?
    /// An object was clicked (or empty space, `nil`).
    var onSelect: ((UUID?) -> Void)?
    /// The object `id` was dragged by `offset` (capture space).
    var onMove: ((UUID, CGSize) -> Void)?

    // In-progress drag state.
    private var dragStart: CGPoint?
    private var strokePoints: [CGPoint] = []
    private var pendingKind: MarkupObject.Kind?
    private var movingID: UUID?
    private var moveOffset: CGSize = .zero

    // In-progress text entry.
    private var textField: NSTextField?
    private var textOriginView: CGPoint?

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
        if let pendingKind {
            MarkupDrawing.draw(MarkupObject(kind: pendingKind, style: activeStyle))
        }
        NSGraphicsContext.restoreGraphicsState()

        if let selected = objects.first(where: { $0.id == selectedID }) {
            let shown = selected.id == movingID ? selected.translated(by: moveOffset) : selected
            drawSelectionHandles(around: toView(shown.bounds))
        }
    }

    private func drawSelectionHandles(around rect: CGRect) {
        let outline = NSBezierPath(rect: rect.insetBy(dx: -3, dy: -3))
        outline.lineWidth = 1
        NSColor.selectedControlColor.setStroke()
        outline.setLineDash([4, 3], count: 2, phase: 0)
        outline.stroke()
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        let point = toCapture(viewPoint)
        switch tool {
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
        case .text:
            beginText(at: viewPoint)
        case .rectangle, .arrow, .freehand, .highlight:
            dragStart = point
            strokePoints = [point]
            updatePending(to: point)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = toCapture(convert(event.locationInWindow, from: nil))
        switch tool {
        case .select where movingID != nil:
            if let start = dragStart {
                moveOffset = CGSize(width: point.x - start.x, height: point.y - start.y)
            }
        case .freehand, .highlight:
            strokePoints.append(point)
            updatePending(to: point)
        case .rectangle, .arrow:
            updatePending(to: point)
        default:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        switch tool {
        case .select:
            if let id = movingID, moveOffset != .zero { onMove?(id, moveOffset) }
        case .rectangle, .arrow, .freehand, .highlight:
            if let kind = pendingKind, Self.isCommittable(kind) { onCommit?(kind) }
        case .text:
            break
        }
        dragStart = nil
        strokePoints = []
        pendingKind = nil
        movingID = nil
        moveOffset = .zero
        needsDisplay = true
    }

    private func updatePending(to point: CGPoint) {
        guard let start = dragStart else { return }
        switch tool {
        case .rectangle:
            pendingKind = .rectangle(CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
                                            width: abs(point.x - start.x), height: abs(point.y - start.y)))
        case .arrow:
            pendingKind = .arrow(from: start, to: point)
        case .freehand:
            pendingKind = .freehand(strokePoints)
        case .highlight:
            pendingKind = .highlight(strokePoints)
        default:
            break
        }
    }

    private static func isCommittable(_ kind: MarkupObject.Kind) -> Bool {
        switch kind {
        case .rectangle(let rect):
            return rect.width > 2 && rect.height > 2
        case .arrow(let from, let to):
            return hypot(to.x - from.x, to.y - from.y) > 4
        case .freehand(let points), .highlight(let points):
            return points.count >= 2
        case .text:
            return true
        }
    }

    // MARK: - Text entry

    private func beginText(at viewPoint: CGPoint) {
        endText() // commit any field already open
        let field = NSTextField()
        field.font = .boldSystemFont(ofSize: activeStyle.fontSize * scale)
        field.textColor = NSColor(activeStyle.stroke)
        field.isBordered = false
        field.drawsBackground = true
        field.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.85)
        field.focusRingType = .none
        field.delegate = self
        let height = max(24, activeStyle.fontSize * scale * 1.4)
        field.frame = CGRect(x: viewPoint.x, y: viewPoint.y, width: 220, height: height)
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
        textOriginView = viewPoint
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        endText()
    }

    private func endText() {
        guard let field = textField, let originView = textOriginView else { return }
        let string = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        textField = nil
        textOriginView = nil
        field.removeFromSuperview()
        guard !string.isEmpty else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: activeStyle.fontSize),
        ]
        let size = (string as NSString).size(withAttributes: attributes)
        let rect = CGRect(origin: toCapture(originView), size: size)
        onCommit?(.text(string, rect))
    }
}
