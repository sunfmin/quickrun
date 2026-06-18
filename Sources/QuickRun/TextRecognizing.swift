import CoreGraphics
import Vision
import QuickRunKit

/// OCR via the Vision framework, configured for the EN-CN dictionary use case:
/// English plus Simplified and Traditional Chinese. Conforms to QuickRunKit's
/// `TextRecognizing` seam, yielding each word with its bounding box so the pure
/// derivation can decide which become clickable Recognized words.
///
/// Vision recognizes lines; this splits each line into words on ICU word
/// boundaries (the same segmentation as double-click-to-select) and asks Vision
/// for each word's box, so the boxes are precise rather than guessed.
final class VisionTextRecognizer: TextRecognizing {
    func recognizeWords(in image: CGImage) -> [OCRObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US", "zh-Hans", "zh-Hant"]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        var result: [OCRObservation] = []
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let string = candidate.string
            // Shared segmentation (ICU + symbol split) so a path's segments are
            // each their own word; boxes come from each segment's range.
            for segment in RecognizedWordExtractor.segments(in: string) {
                let box = Self.wordBox(for: segment.range, in: string, candidate: candidate, lineBox: observation.boundingBox)
                result.append(OCRObservation(text: segment.text, box: box))
            }
        }
        return result
    }

    /// The box for the word at `range`, normalized to the image (bottom-left
    /// origin). Prefers Vision's precise per-substring box; when that can't be
    /// derived, slices the line box by the word's character span rather than
    /// returning the whole line — so a word's hit area never swallows its
    /// neighbours (and is exact for monospace text like a terminal).
    private static func wordBox(for range: Range<String.Index>, in string: String,
                                candidate: VNRecognizedText, lineBox: CGRect) -> CGRect {
        if let observation = try? candidate.boundingBox(for: range) {
            return observation.boundingBox
        }
        let total = string.count
        guard total > 0 else { return lineBox }
        let start = string.distance(from: string.startIndex, to: range.lowerBound)
        let length = string.distance(from: range.lowerBound, to: range.upperBound)
        return CGRect(x: lineBox.minX + CGFloat(start) / CGFloat(total) * lineBox.width,
                      y: lineBox.minY,
                      width: CGFloat(length) / CGFloat(total) * lineBox.width,
                      height: lineBox.height)
    }
}
