import AppKit
import QuickRunKit

extension NSColor {
    convenience init(_ color: RGBAColor) {
        self.init(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }

    var rgba: RGBAColor {
        let c = usingColorSpace(.sRGB) ?? self
        return RGBAColor(red: Double(c.redComponent), green: Double(c.greenComponent),
                         blue: Double(c.blueComponent), alpha: Double(c.alphaComponent))
    }
}

/// Draws Markup objects into the current graphics context, which the caller has
/// already set up so that one unit equals one point of capture space. Shared by
/// the live Editor canvas and the flattening renderer so they never diverge.
enum MarkupDrawing {
    /// Highlighter stroke width and opacity in capture space — a wide, see-through
    /// swipe regardless of the style's line width.
    private static let highlightWidth: CGFloat = 18
    private static let highlightAlpha: CGFloat = 0.35

    /// Draw `object` in the current context (set up as capture space). A blur
    /// region needs the source `image` to sample; pass it whenever a blur could
    /// be present (the live canvas and the flattening renderer both do).
    static func draw(_ object: MarkupObject, image: NSImage? = nil) {
        if case .blur(let rect) = object.kind {
            if let image { Pixelate.draw(region: rect, of: image) }
            return
        }

        let color = NSColor(object.style.stroke)
        let width = CGFloat(object.style.lineWidth)
        color.setStroke()

        switch object.kind {
        case .blur:
            break // handled above
        case .rectangle(let rect):
            let path = NSBezierPath(rect: rect.standardized)
            path.lineWidth = width
            path.stroke()

        case .arrow(let from, let to):
            drawArrow(from: from, to: to, width: width, color: color)

        case .text(let string, let rect):
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: CGFloat(object.style.fontSize)),
                .foregroundColor: color,
            ]
            string.draw(in: rect.standardized, withAttributes: attributes)

        case .freehand(let points):
            let path = strokePath(points)
            path.lineWidth = width
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()

        case .highlight(let points):
            let path = strokePath(points)
            path.lineWidth = highlightWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            color.withAlphaComponent(highlightAlpha).setStroke()
            path.stroke()
        }
    }

    private static func strokePath(_ points: [CGPoint]) -> NSBezierPath {
        let path = NSBezierPath()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.line(to: point) }
        return path
    }

    private static func drawArrow(from: CGPoint, to: CGPoint, width: CGFloat, color: NSColor) {
        let shaft = NSBezierPath()
        shaft.move(to: from)
        shaft.line(to: to)
        shaft.lineWidth = width
        shaft.lineCapStyle = .round
        shaft.stroke()

        let angle = atan2(to.y - from.y, to.x - from.x)
        let headLength = max(12, width * 4)
        let spread = CGFloat.pi / 7
        let left = CGPoint(x: to.x - headLength * cos(angle - spread),
                           y: to.y - headLength * sin(angle - spread))
        let right = CGPoint(x: to.x - headLength * cos(angle + spread),
                            y: to.y - headLength * sin(angle + spread))
        let head = NSBezierPath()
        head.move(to: to)
        head.line(to: left)
        head.line(to: right)
        head.close()
        color.setFill()
        head.fill()
    }
}

/// Destructively pixelates a region of a Capture — redaction. It samples the
/// source down to one colour per block and redraws it blocky, so the fine
/// detail is gone from the output, not merely hidden.
enum Pixelate {
    private static let blockSize: CGFloat = 10

    /// Draw a pixelated copy of `image`'s `region` (capture space) into the
    /// current context at `region`.
    static func draw(region: CGRect, of image: NSImage) {
        let rect = region.standardized
        guard rect.width > 1, rect.height > 1 else { return }
        let columns = max(1, Int((rect.width / blockSize).rounded()))
        let rows = max(1, Int((rect.height / blockSize).rounded()))

        // Average the region down to columns x rows.
        let small = NSImage(size: NSSize(width: columns, height: rows))
        small.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: columns, height: rows),
                   from: rect, operation: .copy, fraction: 1)
        small.unlockFocus()

        // Redraw blocky over the region, destroying the original detail.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.imageInterpolation = .none
        small.draw(in: rect, from: NSRect(x: 0, y: 0, width: columns, height: rows),
                   operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// Flattens the Capture region of a frozen still and its Markup into a single
/// image. In the in-place redesign (ADR 0003) the marks live in frozen-screen
/// point space (bottom-left origin) alongside the still, and the output is the
/// chosen `region` cropped out at native resolution — so anything a mark draws
/// outside the Capture is clipped away.
enum MarkupRenderer {
    /// Render `objects` over `image` (both in frozen-screen point space) and
    /// crop to `region`, at `scale` pixels per point so the result is crisp on
    /// Retina. Marks are clipped to the region.
    static func flatten(image: NSImage, objects: [MarkupObject], region: CGRect, scale: CGFloat) -> NSImage {
        let r = region.standardized
        guard r.width > 0, r.height > 0,
              let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int((r.width * scale).rounded()),
                pixelsHigh: Int((r.height * scale).rounded()),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return image }
        // The rep's logical size is the region in points; the larger pixel
        // backing keeps the still and the strokes sharp at native resolution.
        rep.size = r.size

        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return image }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context

        // Shift frozen-screen space so the region's bottom-left is the output
        // origin, then clip to the region before drawing the still and its marks.
        let transform = NSAffineTransform()
        transform.translateX(by: -r.minX, yBy: -r.minY)
        transform.concat()
        NSBezierPath(rect: r).setClip()

        image.draw(in: NSRect(origin: .zero, size: image.size))
        for object in objects {
            MarkupDrawing.draw(object, image: image)
        }
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let output = NSImage(size: r.size)
        output.addRepresentation(rep)
        return output
    }

    /// PNG data for the flattened Capture, for the clipboard or a file.
    static func pngData(image: NSImage, objects: [MarkupObject], region: CGRect, scale: CGFloat) -> Data? {
        let flattened = flatten(image: image, objects: objects, region: region, scale: scale)
        guard let tiff = flattened.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
