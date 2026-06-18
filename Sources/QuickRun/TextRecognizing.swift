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
            string.enumerateSubstrings(in: string.startIndex..<string.endIndex, options: .byWords) { word, range, _, _ in
                guard let word else { return }
                // Vision's per-substring box is normalized to the image, bottom-
                // left origin; fall back to the line box if it can't be derived.
                let box = (try? candidate.boundingBox(for: range))?.boundingBox ?? observation.boundingBox
                result.append(OCRObservation(text: word, box: box))
            }
        }
        return result
    }
}
