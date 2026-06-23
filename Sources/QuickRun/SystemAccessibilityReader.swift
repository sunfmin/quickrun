import ApplicationServices
import QuickRunKit

/// Reads the selected text of the system-wide focused element via the
/// Accessibility API. Distinguishes "the focused element told us its selection
/// (possibly empty)" from "AX can't read this at all" (nothing focused, or a
/// web/Electron view that exposes no `AXSelectedText`): the former is
/// authoritative — an empty selection means *nothing is selected*, so no
/// clipboard ⌘C is needed — while only the latter defers to the fallback.
/// Requires Accessibility permission.
final class SystemAccessibilityReader: AccessibilitySelectionReading {
    func read() -> AXSelection {
        let systemWide = AXUIElementCreateSystemWide()

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focused
        ) == .success, let focused else { return .unavailable }

        let element = focused as! AXUIElement
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextAttribute as CFString, &value
        ) == .success, let text = value as? String else { return .unavailable }

        return .text(text)
    }
}
