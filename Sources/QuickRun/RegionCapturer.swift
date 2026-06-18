import AppKit

/// Captures a user-selected screen region as an image.
protocol RegionCapturer {
    /// Run an interactive region capture. Calls `completion` on the main queue
    /// with the captured image, or `nil` if the user cancelled.
    func capture(completion: @escaping (NSImage?) -> Void)
}

/// Captures a region by shelling out to macOS's `screencapture -i` (see ADR
/// 0002). The system tool draws the crosshair/region UI and handles multiple
/// displays and Retina; user-initiated interactive capture this way needs no
/// Screen Recording permission. The capture runs off the main thread so the
/// hotkey handler never blocks while the user is dragging out the region.
final class ScreenCaptureRegionCapturer: RegionCapturer {
    private let tool = URL(fileURLWithPath: "/usr/sbin/screencapture")

    func capture(completion: @escaping (NSImage?) -> Void) {
        let output = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("QuickRun-\(UUID().uuidString).png")

        let process = Process()
        process.executableURL = tool
        // -i: interactive region select. The file is written only if the user
        // completes a selection; pressing Esc leaves no file — our "cancelled".
        process.arguments = ["-i", output.path]
        process.terminationHandler = { _ in
            let image = NSImage(contentsOf: output)
            try? FileManager.default.removeItem(at: output)
            DispatchQueue.main.async { completion(image) }
        }

        do {
            try process.run()
        } catch {
            DispatchQueue.main.async { completion(nil) }
        }
    }
}
