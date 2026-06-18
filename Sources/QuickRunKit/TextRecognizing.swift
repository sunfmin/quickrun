import CoreGraphics
import Foundation

/// One word OCR found, with its bounding box normalized to the recognized image
/// (0...1, bottom-left origin — Vision's convention). This is the seam between
/// the framework that reads pixels (Vision, in the app) and the pure derivation
/// of which words become clickable, so that derivation is testable with a fake
/// and no real image.
public struct OCRObservation: Equatable {
    public var text: String
    public var box: CGRect

    public init(text: String, box: CGRect) {
        self.text = text
        self.box = box
    }
}

/// A Recognized word made clickable on the Capture (Live-Text style): the word
/// to look up, and its box normalized to the region image (0...1, bottom-left
/// origin). The overlay maps the box into view points to place the hit area.
public struct RecognizedWord: Equatable {
    public var text: String
    public var box: CGRect

    public init(text: String, box: CGRect) {
        self.text = text
        self.box = box
    }
}

/// Recognizes the words (with boxes) in an image. Vision implements this in the
/// app; the box derivation is tested against a fake conformer, so no real image
/// or Vision is needed to exercise it.
public protocol TextRecognizing {
    func recognizeWords(in image: CGImage) -> [OCRObservation]
}
