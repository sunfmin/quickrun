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

/// Stub capturer returning a fixed result and counting invocations.
final class StubCapturer: SelectionCapturer {
    let result: String?
    private(set) var callCount = 0

    init(_ result: String?) { self.result = result }

    func capture() -> String? {
        callCount += 1
        return result
    }
}

/// Fake Accessibility reader returning a fixed selected text.
final class FakeAXReader: AccessibilitySelectionReading {
    let text: String?
    init(_ text: String?) { self.text = text }
    func selectedText() -> String? { text }
}

final class ClipboardSelectionCapturerTests: XCTestCase {
    func testCaptureReturnsCopiedSelection() {
        let pb = FakePasteboard()
        let capturer = ClipboardSelectionCapturer(pasteboard: pb) { pb.string = "hello" }
        XCTAssertEqual(capturer.capture(), "hello")
    }

    func testCaptureTrimsWhitespace() {
        let pb = FakePasteboard()
        let capturer = ClipboardSelectionCapturer(pasteboard: pb) { pb.string = "  spaced \n" }
        XCTAssertEqual(capturer.capture(), "spaced")
    }

    func testEmptySelectionYieldsNil() {
        let pb = FakePasteboard()
        let capturer = ClipboardSelectionCapturer(pasteboard: pb) { pb.string = "   \n" }
        XCTAssertNil(capturer.capture())
    }

    func testRestoresPreviousClipboardContents() {
        let pb = FakePasteboard()
        pb.string = "user had this"
        let capturer = ClipboardSelectionCapturer(pasteboard: pb) { pb.string = "selected" }
        XCTAssertEqual(capturer.capture(), "selected")
        XCTAssertEqual(pb.string, "user had this")
    }

    func testCopyThatChangesNothingYieldsNilAndLeavesClipboard() {
        let pb = FakePasteboard()
        pb.string = "user had this"
        let capturer = ClipboardSelectionCapturer(pasteboard: pb) { /* nothing copied */ }
        XCTAssertNil(capturer.capture())
        XCTAssertEqual(pb.string, "user had this")
    }
}

final class AXSelectionCapturerTests: XCTestCase {
    func testReturnsTrimmedSelectedText() {
        let capturer = AXSelectionCapturer(reader: FakeAXReader(" hello \n"))
        XCTAssertEqual(capturer.capture(), "hello")
    }

    func testEmptyOrNilYieldsNil() {
        XCTAssertNil(AXSelectionCapturer(reader: FakeAXReader(nil)).capture())
        XCTAssertNil(AXSelectionCapturer(reader: FakeAXReader("  ")).capture())
    }
}

final class ChainedSelectionCapturerTests: XCTestCase {
    func testFirstNonNilWinsAndShortCircuits() {
        let first = StubCapturer("from AX")
        let second = StubCapturer("from clipboard")
        let chained = ChainedSelectionCapturer([first, second])
        XCTAssertEqual(chained.capture(), "from AX")
        XCTAssertEqual(second.callCount, 0, "fallback must not run when AX succeeds")
    }

    func testFallsBackWhenFirstIsNil() {
        let first = StubCapturer(nil)
        let second = StubCapturer("from clipboard")
        let chained = ChainedSelectionCapturer([first, second])
        XCTAssertEqual(chained.capture(), "from clipboard")
        XCTAssertEqual(first.callCount, 1)
    }

    func testAllNilYieldsNil() {
        let chained = ChainedSelectionCapturer([StubCapturer(nil), StubCapturer(nil)])
        XCTAssertNil(chained.capture())
    }
}
