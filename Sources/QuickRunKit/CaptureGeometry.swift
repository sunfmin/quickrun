import CoreGraphics

/// The conversions between the three coordinate spaces the Capture lives in:
///
/// - **overlay view points** — the frozen display's bounds, origin bottom-left
///   (AppKit), where the Capture region and Markup are expressed;
/// - **image pixels** — the frozen still, origin top-left, native Retina
///   resolution, what the crop and Vision consume;
/// - **region-normalized** — 0…1 within the cropped region image, bottom-left
///   origin, where OCR boxes from `RecognizedWordExtractor` come back.
///
/// These flips and scales used to live inline in the overlay controller with no
/// test; a one-pixel error silently cropped the wrong region or misplaced every
/// Recognized word. Holding them in one pure place gives ADR 0003's Retina /
/// multi-display ownership a seam — and a test surface.
public enum CaptureGeometry {
    /// Map a Capture region in overlay view points (bottom-left origin) to the
    /// frozen image's pixel rect (top-left origin, native resolution).
    /// `viewHeight` is the overlay's height in points; `scale` is pixels per
    /// point (the Retina backing scale).
    public static func pixelRect(forViewRect region: CGRect, viewHeight: CGFloat, scale: CGFloat) -> CGRect {
        CGRect(x: region.minX * scale,
               y: (viewHeight - region.maxY) * scale,
               width: region.width * scale,
               height: region.height * scale)
    }

    /// Place a Recognized word's box — normalized 0…1 within the region image,
    /// bottom-left origin — back into overlay view points inside `region`.
    public static func viewRect(forNormalizedBox box: CGRect, in region: CGRect) -> CGRect {
        CGRect(x: region.minX + box.minX * region.width,
               y: region.minY + box.minY * region.height,
               width: box.width * region.width,
               height: box.height * region.height)
    }
}
