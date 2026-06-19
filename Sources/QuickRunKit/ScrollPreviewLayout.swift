import CoreGraphics

/// The pure sizing core of the Scroll Preview (ADR 0004): how the live, no-scrollbar
/// preview of a growing Scroll Capture is displayed beside the Main Box.
///
/// Two regimes, driven only by whether the stitch still fits the screen:
/// - **Growing** — while the stitch's point height fits the available screen
///   height, it is shown 1:1 at the Main Box's width (the capture width). The
///   preview just gets taller as more rows arrive.
/// - **Narrowing** — once the stitch would exceed the available height, the height
///   clamps to that height and the *whole* image scales down proportionally, so the
///   width narrows below the Main Box width and the entire stitch stays visible.
///
/// It touches no pixels, AppKit, or ScreenCaptureKit, so it is testable with
/// synthetic sizes — like `ScrollStitcher`/`RowSignature`.
public enum ScrollPreviewLayout {
    public struct Result: Equatable {
        /// The preview's displayed size in points.
        public let displaySize: CGSize
        /// True once the stitch exceeds the available height and is being scaled
        /// down (the width has narrowed below the Main Box width).
        public let isNarrowing: Bool

        public init(displaySize: CGSize, isNarrowing: Bool) {
            self.displaySize = displaySize
            self.isNarrowing = isNarrowing
        }
    }

    /// Lay out the preview for a stitch of `stitchedPixelSize` pixels, captured at
    /// `scale` backing pixels per point, given `availableHeight` points of screen.
    ///
    /// The Main Box width in points is `stitchedPixelSize.width / scale` (the
    /// capture width). While the stitch's point height is within `availableHeight`,
    /// the preview is that box width tall by the stitch height (not narrowing).
    /// Beyond it, the height is `availableHeight` and the width is the box width
    /// times `availableHeight / stitchHeight` (narrowing).
    public static func layout(stitchedPixelSize: CGSize, scale: CGFloat, availableHeight: CGFloat) -> Result {
        guard scale > 0, availableHeight > 0,
              stitchedPixelSize.width > 0, stitchedPixelSize.height > 0 else {
            return Result(displaySize: .zero, isNarrowing: false)
        }

        let boxWidth = stitchedPixelSize.width / scale
        let stitchHeight = stitchedPixelSize.height / scale

        if stitchHeight <= availableHeight {
            return Result(displaySize: CGSize(width: boxWidth, height: stitchHeight), isNarrowing: false)
        }

        let factor = availableHeight / stitchHeight
        return Result(displaySize: CGSize(width: boxWidth * factor, height: availableHeight), isNarrowing: true)
    }
}
