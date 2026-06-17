import Foundation

/// Captures the text currently selected in the frontmost application.
public protocol SelectionCapturer {
    /// The current Selection, or `nil` if nothing usable is selected.
    func capture() -> String?
}

/// Tries each capturer in order and returns the first non-nil Selection.
/// Used to prefer the Accessibility API and fall back to the clipboard.
public final class ChainedSelectionCapturer: SelectionCapturer {
    private let capturers: [SelectionCapturer]

    public init(_ capturers: [SelectionCapturer]) {
        self.capturers = capturers
    }

    public func capture() -> String? {
        for capturer in capturers {
            if let text = capturer.capture() { return text }
        }
        return nil
    }
}

/// Reads the selected text of the focused UI element via the Accessibility API.
public protocol AccessibilitySelectionReading {
    func selectedText() -> String?
}

/// Captures the Selection through the Accessibility API. Returns nil when no
/// element is focused or it exposes no selected text — letting a fallback run.
public final class AXSelectionCapturer: SelectionCapturer {
    private let reader: AccessibilitySelectionReading

    public init(reader: AccessibilitySelectionReading) {
        self.reader = reader
    }

    public func capture() -> String? {
        let text = reader.selectedText()?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, !text.isEmpty else { return nil }
        return text
    }
}

/// Captures the Selection by triggering a copy and reading the pasteboard, then
/// restoring the pasteboard's previous contents.
///
/// The copy action and the pasteboard are injected so the capture logic is
/// testable without posting real key events or touching `NSPasteboard`. A copy
/// that doesn't change the pasteboard's `changeCount` is treated as "nothing
/// selected" so we never return stale clipboard contents.
public final class ClipboardSelectionCapturer: SelectionCapturer {
    private let pasteboard: PasteboardAccess
    private let copy: () -> Void

    public init(pasteboard: PasteboardAccess, copy: @escaping () -> Void) {
        self.pasteboard = pasteboard
        self.copy = copy
    }

    public func capture() -> String? {
        let previous = pasteboard.string
        let changeCountBefore = pasteboard.changeCount

        copy()

        // No change means the copy produced nothing — nothing was selected.
        guard pasteboard.changeCount != changeCountBefore else { return nil }

        let captured = pasteboard.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        pasteboard.string = previous // restore what the user had

        guard let captured, !captured.isEmpty else { return nil }
        return captured
    }
}
