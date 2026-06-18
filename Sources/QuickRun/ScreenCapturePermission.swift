import AppKit
import CoreGraphics

/// Screen Recording permission: required to freeze the screen with
/// ScreenCaptureKit for an in-place Capture (see ADR 0003). Mirrors
/// `AccessibilityPermission` — first use prompts, and a denial deep-links to the
/// right System Settings pane rather than silently doing nothing.
///
/// Like Accessibility, TCC keys this on a stable signed bundle identity, so it
/// is durable only from the notarized .app bundle (ADR 0001), not a bare
/// SwiftPM binary.
enum ScreenCapturePermission {
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Trigger the system's Screen Recording prompt. Returns the (possibly still
    /// false) grant; macOS only reflects a fresh grant after the app is
    /// relaunched, so callers should guide the user rather than retry in a loop.
    @discardableResult
    static func request() -> Bool { CGRequestScreenCaptureAccess() }

    /// Deep-link straight to the Screen Recording privacy pane in System Settings.
    static func openSettingsPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
