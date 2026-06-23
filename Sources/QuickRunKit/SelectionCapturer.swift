import Foundation

/// What a capturer concluded about the current Selection. The three states matter:
/// a *definite* "nothing selected" must stop the chain, so we never run a more
/// invasive fallback (a synthetic ⌘C) just to re-confirm emptiness — that stray
/// keystroke is what leaked characters into the user's focused field.
public enum CaptureOutcome: Equatable {
    /// A usable, non-empty Selection.
    case selected(String)
    /// Determined that nothing is selected. Stop — don't fall back.
    case empty
    /// This capturer couldn't tell; let the next one try.
    case undetermined

    /// The Selection if one was found, otherwise nil.
    public var selection: String? {
        if case .selected(let text) = self { return text }
        return nil
    }
}

/// Captures the text currently selected in the frontmost application.
public protocol SelectionCapturer {
    func capture() -> CaptureOutcome
}

/// Tries each capturer in order. A `.selected` or a *definite* `.empty` ends the
/// chain; only `.undetermined` (this capturer couldn't tell) advances to the next.
/// This is what lets a known-empty Accessibility read skip the clipboard ⌘C.
public final class ChainedSelectionCapturer: SelectionCapturer {
    private let capturers: [SelectionCapturer]

    public init(_ capturers: [SelectionCapturer]) {
        self.capturers = capturers
    }

    public func capture() -> CaptureOutcome {
        for capturer in capturers {
            switch capturer.capture() {
            case .selected(let text): return .selected(text)
            case .empty: return .empty
            case .undetermined: continue
            }
        }
        return .undetermined
    }
}

/// How the Accessibility API answered when asked for the focused element's
/// selected text.
public enum AXSelection: Equatable {
    /// The focused element exposed its selected text (possibly the empty string,
    /// which authoritatively means "nothing is selected").
    case text(String)
    /// No focused element, or it doesn't expose selected text at all (some web /
    /// Electron views) — the Accessibility read can't decide.
    case unavailable
}

/// Reads the selected text of the focused UI element via the Accessibility API.
public protocol AccessibilitySelectionReading {
    func read() -> AXSelection
}

/// Captures the Selection through the Accessibility API. When AX can read the
/// focused element it answers authoritatively — a real Selection, or a definite
/// empty one — and no clipboard copy is needed. Only when AX can't read at all
/// does it defer (`.undetermined`) to a fallback.
public final class AXSelectionCapturer: SelectionCapturer {
    private let reader: AccessibilitySelectionReading

    public init(reader: AccessibilitySelectionReading) {
        self.reader = reader
    }

    public func capture() -> CaptureOutcome {
        switch reader.read() {
        case .text(let raw):
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? .empty : .selected(trimmed)
        case .unavailable:
            return .undetermined
        }
    }
}

/// Captures the Selection by triggering a copy and reading the pasteboard, then
/// restoring the pasteboard's previous contents. This *does* post a synthetic ⌘C,
/// so it runs only as a last resort — when Accessibility couldn't read the
/// selection at all. A copy that doesn't change the pasteboard's `changeCount` is
/// treated as "nothing selected", so we never return stale clipboard contents.
public final class ClipboardSelectionCapturer: SelectionCapturer {
    private let pasteboard: PasteboardAccess
    private let copy: () -> Void

    public init(pasteboard: PasteboardAccess, copy: @escaping () -> Void) {
        self.pasteboard = pasteboard
        self.copy = copy
    }

    public func capture() -> CaptureOutcome {
        let previous = pasteboard.string
        let changeCountBefore = pasteboard.changeCount

        copy()

        // No change means the copy produced nothing — nothing was selected.
        guard pasteboard.changeCount != changeCountBefore else { return .empty }

        let captured = pasteboard.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        pasteboard.string = previous // restore what the user had

        guard let captured, !captured.isEmpty else { return .empty }
        return .selected(captured)
    }
}
