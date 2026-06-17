import Foundation

/// Captures the text currently selected in the frontmost application.
public protocol SelectionCapturer {
    /// The current Selection, or `nil` if nothing usable is selected.
    func capture() -> String?
}

/// Captures the Selection by triggering a copy and reading the pasteboard.
///
/// The copy action and the pasteboard are injected so the capture logic is
/// testable without posting real key events or touching `NSPasteboard`.
public final class ClipboardSelectionCapturer: SelectionCapturer {
    private let pasteboard: PasteboardAccess
    private let copy: () -> Void

    public init(pasteboard: PasteboardAccess, copy: @escaping () -> Void) {
        self.pasteboard = pasteboard
        self.copy = copy
    }

    public func capture() -> String? {
        copy()
        let text = pasteboard.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, !text.isEmpty else { return nil }
        return text
    }
}
