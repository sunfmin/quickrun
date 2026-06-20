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

    /// Block-averaged row descriptors and the tolerance alignment allows. Real
    /// scrolled rows never byte-match, so a row counts as the same within
    /// `rowTolerance` total difference across `descriptorBlocks` blocks, and a band
    /// is accepted as an alignment when `minMatchRatio` of its rows match.
    /// `minAdvance` is the fewest new rows a frame must add (off either end) to
    /// count as growth. Heuristics, tuned in QA.
    private let descriptorBlocks = 16
    private let rowTolerance = 160 // ~10 average difference per block
    private let minMatchRatio = 0.85
    private let minAdvance = 2

    /// Pixel height of the captured region — a frame is at most this tall, so it
    /// bounds the alignment search and the minimum trustworthy overlap.
    private var heightPixels: Int { Int((region.height * scale).rounded()) }

    /// Require a real shared band before trusting an alignment: at least 8 rows, or
    /// 5% of the frame height — guards against a tiny coincidental match.
    private var tolerance: ScrollStitcher.Tolerance {
        ScrollStitcher.Tolerance(rowTolerance: rowTolerance, minMatchRatio: minMatchRatio,
                                 minOverlap: max(8, heightPixels / 20))
    }

    private var stopped = false

    init(region: CGRect, screen: NSScreen, displayID: CGDirectDisplayID, scale: CGFloat) {
        self.region = region
        self.screen = screen
        self.displayID = displayID
        self.scale = scale
    }

    /// Finish capturing — the loop ends after the frame in flight. Triggered by
    /// Copy / Save (which finalize) or Esc (which cancels).
    func stop() { stopped = true }

    /// Run the capture loop. `onFrame` fires on the main queue with the current
    /// stitched image (point size, native-resolution backing) each time a new
    /// frame is kept, so the Scroll Preview can grow live (ADR 0004). `completion`
    /// fires on the main queue once the loop ends, with the final stitched image
    /// or `nil` if nothing usable was captured — the controller uses it to tear
    /// down and tell apart "finished" from "captured nothing".
    func run(onFrame: @escaping (NSImage) -> Void, completion: @escaping (NSImage?) -> Void) {
        Task {
            let image = await capture(onFrame: onFrame)
            await MainActor.run { completion(image) }
        }
    }

    private func capture(onFrame: @escaping (NSImage) -> Void) async -> NSImage? {
        guard let filter = await makeFilter() else { return nil }
        let config = makeConfig()

        var frames: [CGImage] = []
        var mosaic = ScrollMosaic(tolerance: tolerance, maxShift: heightPixels, minAdvance: minAdvance)
        var latest: NSImage?

        while !stopped && frames.count < maxFrames {
            guard let frame = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else {
                try? await Task.sleep(nanoseconds: interval)
                continue
            }
            let descriptor = RowSignature.descriptors(of: frame, blocks: descriptorBlocks)
            // Align this frame against the page so far. The mosaic grows only when
            // the frame reveals new rows (off the top or bottom) and drops repeats —
            // so the user can scroll freely up and down and still get one whole page.
            guard mosaic.add(descriptor) else {
                try? await Task.sleep(nanoseconds: interval)
                continue
            }
            frames.append(frame)

            // Recomposite and emit so the preview grows. Alignment ran once in
            // `add`; only the blit of the accumulated frames repeats — fine at the
            // grab interval (ADR 0004).
            if let image = composite(frames: frames, placements: mosaic.placements) {
                latest = image
                await MainActor.run { onFrame(image) }
            }
            try? await Task.sleep(nanoseconds: interval)
        }

        return latest
    }

    // MARK: - SCK setup

    private func makeFilter() async -> SCContentFilter? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
              let display = content.displays.first(where: { $0.displayID == displayID }) else { return nil }
        // Exclude QuickRun's own windows so the grab is the live content alone —
        // otherwise the red Main Box outline and the Scroll Preview pane, which
        // float over the display, get baked into the stitched Capture.
        let pid = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == pid }
        return SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
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

    // MARK: - Composite

    /// Composite the kept frames into one tall image at native resolution, each at
    /// its mosaic row `placement`. Later frames draw on top, so the freshest pixels
    /// win in any overlapping band.
    private func composite(frames: [CGImage], placements: [Int]) -> NSImage? {
        guard let totalRows = zip(placements, frames).map({ $0 + $1.height }).max(), totalRows > 0 else { return nil }

        let pixelWidth = frames[0].width
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixelWidth, pixelsHigh: totalRows,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }

        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        let cg = context.cgContext
        // Placements are top-to-bottom; CGContext is bottom-left origin, so a frame
        // at row `p` of height `h` sits at y = totalRows - p - h.
        for (index, frame) in frames.enumerated() {
            let placement = placements[index]
            let rect = CGRect(x: 0, y: totalRows - placement - frame.height,
                              width: pixelWidth, height: frame.height)
            cg.draw(frame, in: rect)
        }

        let pointSize = NSSize(width: CGFloat(pixelWidth) / scale, height: CGFloat(totalRows) / scale)
        let image = NSImage(size: pointSize)
        image.addRepresentation(rep)
        return image
    }
}
