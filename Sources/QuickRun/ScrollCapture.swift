import AppKit
import ScreenCaptureKit
import QuickRunKit

/// The non-interactive overlay drawn over the scroll-capture region while it
/// runs: a bright border and the "Scroll the page to capture more" prompt. Its
/// panel is click-through, so this view never handles events itself.
final class ScrollGuideView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let border = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
        Palette.accent.setStroke()
        border.lineWidth = 2
        border.stroke()

        let text = "Scroll the page to capture more"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let pill = CGRect(x: bounds.midX - textSize.width / 2 - 12, y: 10,
                          width: textSize.width + 24, height: textSize.height + 12)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 8, yRadius: 8).fill()
        (text as NSString).draw(at: CGPoint(x: pill.minX + 12, y: pill.minY + 6), withAttributes: attributes)
    }
}

/// Drives scroll capture (ADR 0004): while the user scrolls the live content
/// under the chosen region, this re-captures the region with ScreenCaptureKit,
/// keeps each frame that adds new rows, and stitches them into one tall image.
/// The user scrolls — QuickRun does not synthesize scrolls — which sidesteps
/// scroll-injection fragility and matches the "Scroll the page to capture more"
/// prompt the overlay shows.
///
/// All the stitching maths is the pure `ScrollStitcher`/`RowSignature` in
/// QuickRunKit; this type is the impure glue (the SCK grabs and the frame loop)
/// that can only be exercised against live content.
final class ScrollCaptureDriver {
    /// `region` is in global screen points (AppKit, bottom-left origin).
    private let region: CGRect
    private let screen: NSScreen
    private let displayID: CGDirectDisplayID
    private let scale: CGFloat

    /// Grab interval — fast enough to catch a normal scroll, with enough overlap
    /// between frames to stitch robustly.
    private let interval: UInt64 = 120_000_000 // 120 ms in nanoseconds
    /// A safety bound on frames so a very long scroll can't grow without limit.
    private let maxFrames = 400

    private var stopped = false

    init(region: CGRect, screen: NSScreen, displayID: CGDirectDisplayID, scale: CGFloat) {
        self.region = region
        self.screen = screen
        self.displayID = displayID
        self.scale = scale
    }

    /// Finish capturing — the loop ends after the frame in flight and stitches
    /// what it has. Triggered by Done or Esc.
    func stop() { stopped = true }

    /// Run the capture loop, calling `completion` on the main queue with the
    /// stitched image (point size, native-resolution backing) or `nil` if nothing
    /// usable was captured.
    func run(completion: @escaping (NSImage?) -> Void) {
        Task {
            let image = await capture()
            await MainActor.run { completion(image) }
        }
    }

    private func capture() async -> NSImage? {
        guard let filter = await makeFilter() else { return nil }
        let config = makeConfig()

        var frames: [CGImage] = []
        var signatures: [[UInt64]] = []

        while !stopped && frames.count < maxFrames {
            if let frame = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                let signature = RowSignature.rows(of: frame)
                // Keep a frame only when it differs from the last kept one — i.e.
                // the user scrolled and new rows appeared. A still page captures
                // one frame and waits.
                let isNew = signatures.last.map { !ScrollStitcher.reachedEnd($0, signature) } ?? true
                if isNew {
                    frames.append(frame)
                    signatures.append(signature)
                }
            }
            try? await Task.sleep(nanoseconds: interval)
        }

        guard !frames.isEmpty else { return nil }
        return stitch(frames: frames, signatures: signatures)
    }

    // MARK: - SCK setup

    private func makeFilter() async -> SCContentFilter? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
              let display = content.displays.first(where: { $0.displayID == displayID }) else { return nil }
        return SCContentFilter(display: display, excludingWindows: [])
    }

    private func makeConfig() -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        // sourceRect is the region in points, display-local, top-left origin.
        config.sourceRect = CGRect(
            x: region.minX - screen.frame.minX,
            y: screen.frame.maxY - region.maxY,
            width: region.width,
            height: region.height)
        config.width = Int((region.width * scale).rounded())
        config.height = Int((region.height * scale).rounded())
        config.showsCursor = false
        return config
    }

    // MARK: - Stitch

    /// Composite the frames into one tall image at native resolution, placing each
    /// at the row offset ScrollStitcher derived from the signatures.
    private func stitch(frames: [CGImage], signatures: [[UInt64]]) -> NSImage? {
        let offsets = ScrollStitcher.offsets(forFrames: signatures)
        let totalRows = ScrollStitcher.stitchedHeight(forFrames: signatures)
        guard totalRows > 0 else { return nil }

        let pixelWidth = frames[0].width
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixelWidth, pixelsHigh: totalRows,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }

        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        let cg = context.cgContext
        // Row signatures are top-to-bottom; CGContext is bottom-left origin, so a
        // frame at row offset `o` of height `h` sits at y = totalRows - o - h.
        for (index, frame) in frames.enumerated() {
            let offset = offsets[index]
            let rect = CGRect(x: 0, y: totalRows - offset - frame.height,
                              width: pixelWidth, height: frame.height)
            cg.draw(frame, in: rect)
        }

        let pointSize = NSSize(width: CGFloat(pixelWidth) / scale, height: CGFloat(totalRows) / scale)
        let image = NSImage(size: pointSize)
        image.addRepresentation(rep)
        return image
    }
}
