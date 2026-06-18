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
    static func draw(_ object: MarkupObject) {
        NSColor(object.style.stroke).setStroke()
        switch object.kind {
        case .rectangle(let rect):
            let path = NSBezierPath(rect: rect.standardized)
            path.lineWidth = CGFloat(object.style.lineWidth)
            path.stroke()
        }
    }
}

/// Flattens a Capture and its Markup into a single image.
enum MarkupRenderer {
    /// Render `objects` over `image` at the image's native resolution, in
    /// capture space (bottom-left origin), and return the composited image.
    static func flatten(image: NSImage, objects: [MarkupObject]) -> NSImage {
        let logical = image.size
        let pixel = pixelSize(of: image)
        guard logical.width > 0, logical.height > 0,
              let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(pixel.width.rounded()),
                pixelsHigh: Int(pixel.height.rounded()),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return image }
        // Setting the rep's logical size establishes the drawing coordinate
        // system; the larger pixel backing means strokes stay crisp at native res.
        rep.size = logical

        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return image }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(origin: .zero, size: logical))
        for object in objects {
            MarkupDrawing.draw(object)
        }
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let output = NSImage(size: logical)
        output.addRepresentation(rep)
        return output
    }

    /// PNG data for the flattened image, for the clipboard or a file.
    static func pngData(image: NSImage, objects: [MarkupObject]) -> Data? {
        let flattened = flatten(image: image, objects: objects)
        guard let tiff = flattened.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func pixelSize(of image: NSImage) -> NSSize {
        let pixels = image.representations.reduce(NSSize.zero) { acc, rep in
            NSSize(width: max(acc.width, CGFloat(rep.pixelsWide)),
                   height: max(acc.height, CGFloat(rep.pixelsHigh)))
        }
        return pixels == .zero ? image.size : pixels
    }
}
