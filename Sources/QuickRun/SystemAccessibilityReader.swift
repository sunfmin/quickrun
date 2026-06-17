import ApplicationServices
import QuickRunKit

/// Reads the selected text of the system-wide focused element via the
/// Accessibility API. Returns nil when nothing is focused or the element
/// exposes no `AXSelectedText` (e.g. some web/Electron views), so the clipboard
/// fallback can take over. Requires Accessibility permission.
final class SystemAccessibilityReader: AccessibilitySelectionReading {
    func selectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focused
        ) == .success, let focused else { return nil }

        let element = focused as! AXUIElement
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextAttribute as CFString, &value
        ) == .success, let text = value as? String else { return nil }

        return text
    }
}
