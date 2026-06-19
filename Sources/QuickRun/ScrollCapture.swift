import AppKit
import ScreenCaptureKit
import QuickRunKit

/// Drives scroll capture (ADR 0004): re-captures a region with ScreenCaptureKit
/// while sending scroll-wheel events to the content under it, detects when each
/// new frame stops adding rows (or the user stops), and stitches the frames into
/// one tall image. The frozen-overlay capture path is untouched; this is the
/// separate, non-in-place engine.
///
/// All the stitching maths is the pure `ScrollStitcher`/`RowSignature` in
/// QuickRunKit; this type is the impure glue — the SCK stream and the synthesized
/// scrolls — that can only be exercised against live content.
final class ScrollCaptureDriver {
    /// `region` is in global screen points (AppKit, bottom-left origin).
    private let region: CGRect
    private let screen: NSScreen
    private let displayID: CGDirectDisplayID
    private let scale: CGFloat

    /// Stop after this many frames even if the end isn't detected, so a region
    /// over endlessly-loading content can't capture forever.
    private let maxFrames = 40
    /// Pause after each scroll so the content settles before the next grab.
    private let settle: UInt64 = 280_000_000 // 280 ms in nanoseconds

    private var stopped = false

    init(region: CGRect, screen: NSScreen, displayID: CGDirectDisplayID, scale: CGFloat) {
        self.region = region
        self.screen = screen
        self.displayID = displayID
        self.scale = scale
    }

    /// Stop early (the user pressed Esc / clicked Stop). The loop ends after the
    /// frame in flight and stitches what it has.
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

        warpCursorToRegionCenter()

        var frames: [CGImage] = []
        var signatures: [[UInt64]] = []

        while frames.count < maxFrames && !stopped {
            guard let frame = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else {
                break
            }
            let signature = RowSignature.rows(of: frame)
            if let previous = signatures.last, ScrollStitcher.reachedEnd(previous, signature) {
                break // a frame that added nothing — end of the content
            }
            frames.append(frame)
            signatures.append(signature)

            postScrollDown()
            try? await Task.sleep(nanoseconds: settle)
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

    // MARK: - Scroll injection

    /// Scroll the content under the region down by about half the region's height,
    /// so consecutive frames overlap heavily (robust against sub-pixel drift).
    private func postScrollDown() {
        let delta = Int32(-(region.height * 0.5)) // negative wheel1 advances content
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                            wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0)
        event?.post(tap: .cghidEventTap)
    }

    /// Move the cursor into the region so the scroll events land on the content
    /// there. Global coordinates here are top-left origin (Core Graphics), flipped
    /// from AppKit around the main display's height.
    private func warpCursorToRegionCenter() {
        let mainHeight = NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height
            ?? screen.frame.height
        let center = CGPoint(x: region.midX, y: mainHeight - region.midY)
        CGWarpMouseCursorPosition(center)
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
