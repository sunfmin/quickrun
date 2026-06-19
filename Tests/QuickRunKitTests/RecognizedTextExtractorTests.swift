import XCTest
import CoreGraphics
@testable import QuickRunKit

final class RecognizedTextExtractorTests: XCTestCase {
    /// Boxes are normalized, bottom-left origin — a larger `y` is higher on the
    /// Capture. Fixed size; only position decides line grouping and order.
    private func obs(_ text: String, x: Double, y: Double) -> OCRObservation {
        OCRObservation(text: text, box: CGRect(x: x, y: y, width: 0.2, height: 0.08))
    }

    func testOrdersLinesTopToBottomAndWordsLeftToRight() {
        // Deliberately shuffled input; both within and across lines.
        let words = [
            obs("world", x: 0.4, y: 0.8),
            obs("line", x: 0.4, y: 0.5),
            obs("Hello", x: 0.1, y: 0.8),
            obs("second", x: 0.1, y: 0.5),
        ]
        XCTAssertEqual(RecognizedTextExtractor.text(from: words), "Hello world\nsecond line")
    }

    func testSortsWordsWithinAOneLineBlockLeftToRight() {
        let words = [obs("c", x: 0.7, y: 0.5), obs("a", x: 0.1, y: 0.5), obs("b", x: 0.4, y: 0.5)]
        XCTAssertEqual(RecognizedTextExtractor.text(from: words), "a b c")
    }

    func testDropsBlankAndWhitespaceObservations() {
        let words = [obs("real", x: 0.1, y: 0.5), obs("   ", x: 0.4, y: 0.5), obs("", x: 0.7, y: 0.5)]
        XCTAssertEqual(RecognizedTextExtractor.text(from: words), "real")
    }

    func testKeepsRepeatsUnlikeTheDedupedSidebar() {
        let words = [obs("the", x: 0.1, y: 0.5), obs("the", x: 0.4, y: 0.5)]
        XCTAssertEqual(RecognizedTextExtractor.text(from: words), "the the")
    }

    func testNoObservationsYieldsEmptyString() {
        XCTAssertEqual(RecognizedTextExtractor.text(from: []), "")
        XCTAssertEqual(RecognizedTextExtractor.text(from: [obs("  ", x: 0, y: 0)]), "")
    }

    func testSlightBaselineJitterStaysOnOneLine() {
        // Two words nudged a hair vertically still read as one line.
        let words = [obs("on", x: 0.1, y: 0.50), obs("line", x: 0.4, y: 0.51)]
        XCTAssertEqual(RecognizedTextExtractor.text(from: words), "on line")
    }
}
