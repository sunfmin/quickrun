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
        // Order matters: Vision biases recognition toward the first language, and
        // with "en-US" first it returns *nothing* for any image containing Chinese
        // (verified on revision 3 / macOS 26). Chinese first recognizes both CJK
        // and English with no English regression — so it leads.
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]

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
            // each their own word. Ask Vision for each word's real box via
            // boundingBox(for:) — the range indexes candidate.string, so it lines
            // up — which honours actual glyph widths. A proportional font would
            // otherwise drift: slicing the line box by character count assumes a
            // uniform width and misplaces words later in the line. Fall back to
            // the character-proportional slice only when Vision gives no box.
            for segment in RecognizedWordExtractor.segments(in: string) {
                let visionBox = (try? candidate.boundingBox(for: segment.range)) ?? nil
                let box = visionBox?.boundingBox
                    ?? RecognizedWordExtractor.wordBox(in: observation.boundingBox, line: string, range: segment.range)
                result.append(OCRObservation(text: segment.text, box: box))
            }
        }
        return result
    }
}
