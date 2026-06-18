import XCTest
@testable import QuickRunKit

final class RecognizedWordExtractorTests: XCTestCase {
    func testSplitsOnWhitespaceAndDropsPunctuation() {
        XCTAssertEqual(RecognizedWordExtractor.words(from: ["Hello, world!"]), ["Hello", "world"])
    }

    func testKeepsContractionsWhole() {
        XCTAssertEqual(RecognizedWordExtractor.words(from: ["I don't know"]), ["I", "don't", "know"])
    }

    func testSplitsHyphenatedWords() {
        XCTAssertEqual(RecognizedWordExtractor.words(from: ["well-being"]), ["well", "being"])
    }

    func testSegmentsChineseIntoMultipleWords() {
        let words = RecognizedWordExtractor.words(from: ["你好世界"])
        XCTAssertGreaterThan(words.count, 1, "CJK must be segmented, not one blob")
        XCTAssertTrue(words.contains("世界"))
        XCTAssertEqual(words.joined(), "你好世界", "segmentation must lose no characters")
    }

    func testHandlesMixedEnglishAndChinese() {
        XCTAssertEqual(RecognizedWordExtractor.words(from: ["Hello 世界"]), ["Hello", "世界"])
    }

    func testDeduplicatesCaseInsensitivelyKeepingFirstForm() {
        XCTAssertEqual(RecognizedWordExtractor.words(from: ["The the THE Cat"]), ["The", "Cat"])
    }

    func testPreservesFirstSeenOrderAcrossLines() {
        XCTAssertEqual(
            RecognizedWordExtractor.words(from: ["alpha beta", "gamma alpha"]),
            ["alpha", "beta", "gamma"]
        )
    }

    func testEmptyAndWhitespaceYieldNoWords() {
        XCTAssertEqual(RecognizedWordExtractor.words(from: ["", "   ", "\n\t"]), [])
        XCTAssertEqual(RecognizedWordExtractor.words(from: []), [])
    }
}
