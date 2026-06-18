import AppKit
import ScreenCaptureKit

/// A still of one display, frozen the instant the hotkey fired — the surface the
/// Editor overlay draws and the Capture is cropped from.
struct FrozenDisplay {
    /// The captured pixels (top-left origin, native Retina resolution).
    let image: CGImage
    /// The display's frame in global screen points (AppKit, bottom-left origin) —
    /// where the borderless overlay window is placed so it sits exactly over the
    /// frozen content.
    let frame: CGRect
    /// Pixels per point, so the overlay can map a point-space region to an image
    /// pixel rect for cropping.
    let scale: CGFloat
    /// The screen the still came from, for placing the overlay window.
    let screen: NSScreen
}

/// Freezes the display under the cursor with ScreenCaptureKit (macOS 14+). This
/// is the in-place capture's foundation (ADR 0003): owning the still means
/// owning the selection coordinates that `screencapture -i` never reported.
///
/// v1 freezes only the one display the cursor is on (per the redesign's stated
/// default); multi-display spanning is a later concern.
enum DisplayFreezer {
    /// Capture the display under the cursor and call `completion` on the main
    /// queue with the frozen still, or `nil` if capture failed (e.g. permission
    /// not yet granted, or no matching display).
    static func freezeDisplayUnderCursor(completion: @escaping (FrozenDisplay?) -> Void) {
        let mouse = NSEvent.mouseLocation // global points, bottom-left origin
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let screen, let displayID = screen.displayID else {
            completion(nil)
            return
        }
        let scale = screen.backingScaleFactor

        Task {
            let frozen = await capture(displayID: displayID, screen: screen, scale: scale)
            await MainActor.run { completion(frozen) }
        }
    }

    private static func capture(displayID: CGDirectDisplayID, screen: NSScreen, scale: CGFloat) async -> FrozenDisplay? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return nil }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            // Capture at native resolution so the Capture is crisp on Retina; the
            // overlay view is sized in points and scales the image down to fit.
            config.width = Int((screen.frame.width * scale).rounded())
            config.height = Int((screen.frame.height * scale).rounded())
            config.showsCursor = false

            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return FrozenDisplay(image: image, frame: screen.frame, scale: scale, screen: screen)
        } catch {
            return nil
        }
    }
}

extension NSScreen {
    /// The Core Graphics display ID backing this screen, read from its device
    /// description (the key AppKit publishes it under).
    var displayID: CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value
    }
}
