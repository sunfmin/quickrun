import AppKit
import Vision

/// Recognizes the text in a Capture, returning the recognized lines.
protocol TextRecognizing {
    /// The lines of text found in `image`, in Vision's reading order. Runs
    /// synchronously — call it off the main thread.
    func recognizedLines(in image: NSImage) -> [String]
}

/// OCR via the Vision framework, configured for the EN-CN dictionary use case:
/// English plus Simplified and Traditional Chinese.
final class VisionTextRecognizer: TextRecognizing {
    func recognizedLines(in image: NSImage) -> [String] {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US", "zh-Hans", "zh-Hant"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }
}
