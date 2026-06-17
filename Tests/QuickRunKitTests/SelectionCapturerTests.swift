import XCTest
@testable import QuickRunKit

/// In-memory `PasteboardAccess` for tests.
final class FakePasteboard: PasteboardAccess {
    var string: String? {
        didSet { changeCount += 1 }
    }
    private(set) var changeCount = 0

    init(string: String? = nil) { self.string = string }
}

final class ClipboardSelectionCapturerTests: XCTestCase {
    func testCaptureReturnsCopiedSelection() {
        let pb = FakePasteboard()
        // The copy action simulates the frontmost app writing its selection.
        let capturer = ClipboardSelectionCapturer(pasteboard: pb) {
            pb.string = "hello"
        }
        XCTAssertEqual(capturer.capture(), "hello")
    }

    func testCaptureTrimsWhitespace() {
        let pb = FakePasteboard()
        let capturer = ClipboardSelectionCapturer(pasteboard: pb) {
            pb.string = "  spaced \n"
        }
        XCTAssertEqual(capturer.capture(), "spaced")
    }

    func testEmptySelectionYieldsNil() {
        let pb = FakePasteboard()
        let capturer = ClipboardSelectionCapturer(pasteboard: pb) {
            pb.string = "   \n"
        }
        XCTAssertNil(capturer.capture())
    }

    func testNoPasteboardContentYieldsNil() {
        let pb = FakePasteboard()
        let capturer = ClipboardSelectionCapturer(pasteboard: pb) { /* nothing copied */ }
        XCTAssertNil(capturer.capture())
    }
}
