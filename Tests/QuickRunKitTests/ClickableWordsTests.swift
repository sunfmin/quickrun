import XCTest
import CoreGraphics
@testable import QuickRunKit

/// A fake recognizer that returns canned word observations and ignores the
/// image, so the word/box derivation is tested without Vision or a real image.
private struct FakeTextRecognizer: TextRecognizing {
    let observations: [OCRObservation]
    func recognizeWords(in image: CGImage) -> [OCRObservation] { observations }
}

/// A 1×1 image to feed the fake — never inspected, just satisfies the seam.
private func dummyImage() -> CGImage {
    let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
                            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return context.makeImage()!
}

final class ClickableWordsTests: XCTestCase {
    private func obs(_ text: String, _ box: CGRect = .zero) -> OCRObservation {
        OCRObservation(text: text, box: box)
    }

    func testKeepsTheWordAndItsBox() {
        let box = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.05)
        let words = RecognizedWordExtractor.clickableWords(from: [obs("hello", box)])
        XCTAssertEqual(words, [RecognizedWord(text: "hello", box: box)])
    }

    func testDropsPureNumbersAndLoneLatinLetters() {
        let words = RecognizedWordExtractor.clickableWords(from: [
            obs("cat"), obs("h"), obs("2026"), obs("a"),
        ])
        XCTAssertEqual(words.map(\.text), ["cat"])
    }

    func testKeepsSingleCJKCharacters() {
        let words = RecognizedWordExtractor.clickableWords(from: [obs("时"), obs("好")])
        XCTAssertEqual(words.map(\.text), ["时", "好"])
    }

    func testKeepsEveryOccurrenceWithItsOwnBox() {
        // In-place words are not de-duplicated: each spot a word appears on the
        // Capture is independently clickable, so all three boxes survive.
        let a = CGRect(x: 0, y: 0, width: 0.2, height: 0.1)
        let b = CGRect(x: 0.5, y: 0.5, width: 0.2, height: 0.1)
        let c = CGRect(x: 0.5, y: 0.8, width: 0.2, height: 0.1)
        let words = RecognizedWordExtractor.clickableWords(from: [
            obs("The", a), obs("the", b), obs("THE", c),
        ])
        XCTAssertEqual(words, [
            RecognizedWord(text: "The", box: a),
            RecognizedWord(text: "the", box: b),
            RecognizedWord(text: "THE", box: c),
        ])
    }

    func testPreservesObservationOrder() {
        let words = RecognizedWordExtractor.clickableWords(from: [
            obs("alpha"), obs("beta"), obs("gamma"),
        ])
        XCTAssertEqual(words.map(\.text), ["alpha", "beta", "gamma"])
    }

    func testTrimsWhitespaceAndIgnoresBlankObservations() {
        let words = RecognizedWordExtractor.clickableWords(from: [
            obs("  cat  "), obs("   "), obs(""),
        ])
        XCTAssertEqual(words.map(\.text), ["cat"])
    }

    func testDerivesThroughTheRecognizingSeam() {
        let fake = FakeTextRecognizer(observations: [
            obs("paw", CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1)),
            obs("3"),
            obs("爪", CGRect(x: 0.4, y: 0.1, width: 0.1, height: 0.1)),
        ])
        let words = RecognizedWordExtractor.clickableWords(from: fake.recognizeWords(in: dummyImage()))
        XCTAssertEqual(words.map(\.text), ["paw", "爪"])
    }
}
