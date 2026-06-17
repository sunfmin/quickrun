import AppKit
import Carbon.HIToolbox

/// Posts a synthetic ⌘C to the frontmost app so the current selection lands on
/// the pasteboard. Requires Accessibility permission to actually deliver events;
/// without it the post is a silent no-op.
enum SystemCopy {
    static func copySelection() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let cKey = CGKeyCode(kVK_ANSI_C)

        let down = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: false)
        up?.flags = .maskCommand

        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)

        // Give the target app a moment to write to the pasteboard before we read.
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
}
