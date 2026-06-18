import XCTest
@testable import QuickRunKit

final class RecognizedWordExtractorTests: XCTestCase {
    func testSplitsOnWhitespaceAndDropsPunctuation() {
        XCTAssertEqual(RecognizedWordExtractor.words(from: ["Hello, world!"]), ["Hello", "world"])
    }

    func testKeepsContractionsWhole() {
        XCTAssertEqual(RecognizedWordExtractor.words(from: ["we don't know"]), ["we", "don't", "know"])
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

    func testDropsLoneLatinLettersAndPureNumbers() {
        // "I" and "a" are casualties of dropping single Latin letters, but the
        // OCR specks "h" and "1" — the real noise — go with them.
        XCTAssertEqual(RecognizedWordExtractor.words(from: ["a cat h sat 1 时 2026"]), ["cat", "sat", "时"])
    }

    func testKeepsSingleCJKCharacters() {
        XCTAssertEqual(RecognizedWordExtractor.words(from: ["你 好"]), ["你", "好"])
    }

    func testEmptyAndWhitespaceYieldNoWords() {
        XCTAssertEqual(RecognizedWordExtractor.words(from: ["", "   ", "\n\t"]), [])
        XCTAssertEqual(RecognizedWordExtractor.words(from: []), [])
    }

    // MARK: - Splitting symbol-joined tokens (paths, file names)

    func testSplitsFileNameOnTheDot() {
        XCTAssertEqual(RecognizedWordExtractor.words(from: ["QuickRun.app"]), ["QuickRun", "app"])
    }

    func testSplitsDirectoryPathIntoSegments() {
        XCTAssertEqual(
            RecognizedWordExtractor.words(from: ["/opt/homebrew/Caskroom/quickrun"]),
            ["opt", "homebrew", "Caskroom", "quickrun"]
        )
    }

    func testSplitsOnUnderscore() {
        XCTAssertEqual(RecognizedWordExtractor.words(from: ["foo_bar"]), ["foo", "bar"])
    }

    func testKeepsApostropheWordsWhileSplittingSymbols() {
        XCTAssertEqual(RecognizedWordExtractor.words(from: ["can't.stop"]), ["can't", "stop"])
    }

    func testSegmentRangesRecoverTheirText() {
        let line = "/Applications/QuickRun.app"
        let segments = RecognizedWordExtractor.segments(in: line)
        XCTAssertEqual(segments.map(\.text), ["Applications", "QuickRun", "app"])
        // Each range must point back at its own text in the original line.
        for segment in segments {
            XCTAssertEqual(String(line[segment.range]), segment.text)
        }
    }

    // MARK: - Per-word boxes (sliced from the line box, so they don't merge)

    private func box(of word: String, in line: String, lineBox: CGRect) -> CGRect {
        let range = line.range(of: word)!
        return RecognizedWordExtractor.wordBox(in: lineBox, line: line, range: range)
    }

    func testWordBoxesAreDistinctSlicesOfTheLine() {
        let line = "ab cd"
        let lineBox = CGRect(x: 0, y: 0, width: 1, height: 0.1) // 5 chars, width 1
        let ab = box(of: "ab", in: line, lineBox: lineBox)
        let cd = box(of: "cd", in: line, lineBox: lineBox)
        XCTAssertEqual(ab, CGRect(x: 0, y: 0, width: 0.4, height: 0.1))   // chars 0..2 of 5
        XCTAssertEqual(cd, CGRect(x: 0.6, y: 0, width: 0.4, height: 0.1)) // chars 3..5 of 5
        XCTAssertFalse(ab.intersects(cd), "adjacent words must not share a box")
    }

    func testCJKCountsDoubleWidthWhenSlicing() {
        let line = "中a"                                  // widths 2 + 1 = 3
        let lineBox = CGRect(x: 0, y: 0, width: 3, height: 1)
        let cjk = box(of: "中", in: line, lineBox: lineBox)
        let latin = box(of: "a", in: line, lineBox: lineBox)
        XCTAssertEqual(cjk, CGRect(x: 0, y: 0, width: 2, height: 1))
        XCTAssertEqual(latin, CGRect(x: 2, y: 0, width: 1, height: 1))
    }
}
