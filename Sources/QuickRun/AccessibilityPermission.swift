import AppKit
import ApplicationServices

/// Accessibility permission: required both to read the Selection via the
/// Accessibility API and to post the synthetic ⌘C used by the clipboard
/// fallback.
///
/// Note: TCC keys this permission on a stable, signed bundle identity. A plain
/// SwiftPM binary grants unreliably; durable behavior needs the notarized .app
/// bundle (see ADR-0001).
enum AccessibilityPermission {
    static var isGranted: Bool { AXIsProcessTrusted() }

    /// Show the system prompt that offers to open the Accessibility pane.
    static func prompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Deep-link straight to the Accessibility privacy pane in System Settings.
    static func openSettingsPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
