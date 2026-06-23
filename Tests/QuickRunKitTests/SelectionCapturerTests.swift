import XCTest
@testable import QuickRunKit

/// In-memory `PasteboardAccess` for tests. `changeCount` advances on every set
/// (matching `NSPasteboard`), but not during `init`.
final class FakePasteboard: PasteboardAccess {
    var string: String? {
        didSet { changeCount += 1 }
    }
    private(set) var changeCount = 0

    init(string: String? = nil) { self.string = string }
}

/// Stub capturer returning a fixed outcome and counting invocations.
final class StubCapturer: SelectionCapturer {
    let result: CaptureOutcome
    private(set) var callCount = 0

    init(_ result: CaptureOutcome) { self.result = result }

    func capture() -> CaptureOutcome {
        callCount += 1
        return result
    }
}

/// Fake Accessibility reader returning a fixed answer.
final class FakeAXReader: AccessibilitySelectionReading {
    let answer: AXSelection
    init(_ answer: AXSelection) { self.answer = answer }
    func read() -> AXSelection { answer }
}

final class ClipboardSelectionCapturerTests: XCTestCase {
    func testCaptureReturnsCopiedSelection() {
        let pb = FakePasteboard()
        let capturer = ClipboardSelectionCapturer(pasteboard: pb) { pb.string = "hello" }
        XCTAssertEqual(capturer.capture(), .selected("hello"))
    }

    func testCaptureTrimsWhitespace() {
        let pb = FakePasteboard()
        let capturer = ClipboardSelectionCapturer(pasteboard: pb) { pb.string = "  spaced \n" }
        XCTAssertEqual(capturer.capture(), .selected("spaced"))
    }

    func testEmptySelectionYieldsEmpty() {
        let pb = FakePasteboard()
        let capturer = ClipboardSelectionCapturer(pasteboard: pb) { pb.string = "   \n" }
        XCTAssertEqual(capturer.capture(), .empty)
    }

    func testRestoresPreviousClipboardContents() {
        let pb = FakePasteboard()
        pb.string = "user had this"
        let capturer = ClipboardSelectionCapturer(pasteboard: pb) { pb.string = "selected" }
        XCTAssertEqual(capturer.capture(), .selected("selected"))
        XCTAssertEqual(pb.string, "user had this")
    }

    func testCopyThatChangesNothingYieldsEmptyAndLeavesClipboard() {
        let pb = FakePasteboard()
        pb.string = "user had this"
        let capturer = ClipboardSelectionCapturer(pasteboard: pb) { /* nothing copied */ }
        XCTAssertEqual(capturer.capture(), .empty)
        XCTAssertEqual(pb.string, "user had this")
    }
}

final class AXSelectionCapturerTests: XCTestCase {
    func testReturnsTrimmedSelectedText() {
        let capturer = AXSelectionCapturer(reader: FakeAXReader(.text(" hello \n")))
        XCTAssertEqual(capturer.capture(), .selected("hello"))
    }

    /// A focused element that reports an empty selection is a *definite* empty —
    /// the key distinction that lets the chain skip the clipboard ⌘C.
    func testEmptyAXSelectionIsDefiniteEmpty() {
        XCTAssertEqual(AXSelectionCapturer(reader: FakeAXReader(.text("  "))).capture(), .empty)
        XCTAssertEqual(AXSelectionCapturer(reader: FakeAXReader(.text(""))).capture(), .empty)
    }

    /// AX that can't read at all stays undetermined, so a fallback may run.
    func testUnavailableAXIsUndetermined() {
        XCTAssertEqual(AXSelectionCapturer(reader: FakeAXReader(.unavailable)).capture(), .undetermined)
    }
}

final class ChainedSelectionCapturerTests: XCTestCase {
    func testFirstSelectedWinsAndShortCircuits() {
        let first = StubCapturer(.selected("from AX"))
        let second = StubCapturer(.selected("from clipboard"))
        let chained = ChainedSelectionCapturer([first, second])
        XCTAssertEqual(chained.capture(), .selected("from AX"))
        XCTAssertEqual(second.callCount, 0, "fallback must not run when AX succeeds")
    }

    func testFallsBackWhenFirstIsUndetermined() {
        let first = StubCapturer(.undetermined)
        let second = StubCapturer(.selected("from clipboard"))
        let chained = ChainedSelectionCapturer([first, second])
        XCTAssertEqual(chained.capture(), .selected("from clipboard"))
        XCTAssertEqual(first.callCount, 1)
    }

    /// The regression test for the stray-"C" bug: a definite empty from AX must
    /// STOP the chain, never triggering the clipboard's speculative ⌘C.
    func testDefiniteEmptyStopsBeforeClipboardFallback() {
        let ax = StubCapturer(.empty)
        let clipboard = StubCapturer(.selected("should never run"))
        let chained = ChainedSelectionCapturer([ax, clipboard])
        XCTAssertEqual(chained.capture(), .empty)
        XCTAssertEqual(clipboard.callCount, 0,
                       "a definite empty from AX must NOT fire the clipboard ⌘C fallback")
    }

    func testAllUndeterminedYieldsUndetermined() {
        let chained = ChainedSelectionCapturer([StubCapturer(.undetermined), StubCapturer(.undetermined)])
        XCTAssertEqual(chained.capture(), .undetermined)
    }
}
