import CoreGraphics
import Foundation

/// Reconstructs the full recognized text of a Capture in natural reading order
/// from word-level OCR observations — the text behind the Editor's "Copy text"
/// action.
///
/// Vision reports each word with a box but no reading order; this recovers the
/// order geometrically so the seam stays pure (testable with synthetic boxes, no
/// Vision), the same way `clickableWords` derives clickable hits. Boxes are
/// normalized 0…1 with a bottom-left origin, so a *larger* y is *higher* on the
/// Capture.
///
/// Unlike the sidebar's de-duplicated `RecognizedWordExtractor.words`, this keeps
/// every word: the point of Copy-text is the whole block, repeats and all.
public enum RecognizedTextExtractor {
    /// Group the observations into lines by vertical overlap, order the lines
    /// top→bottom and the words within each line left→right, and join lines with
    /// newlines and words with a single space. Blank observations are dropped;
    /// no observations yields the empty string.
    public static func text(from observations: [OCRObservation]) -> String {
        let words = observations.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !words.isEmpty else { return "" }

        // Walk words top→bottom; each joins the first line it vertically overlaps
        // or starts a new one. Processing in y order keeps a line's members
        // contiguous so the overlap test compares like with like.
        var lines: [[OCRObservation]] = []
        for word in words.sorted(by: { $0.box.standardized.midY > $1.box.standardized.midY }) {
            if let index = lines.firstIndex(where: { line in
                line.contains { sameLine($0.box, word.box) }
            }) {
                lines[index].append(word)
            } else {
                lines.append([word])
            }
        }

        return lines
            .sorted { lineMidY($0) > lineMidY($1) }
            .map { line in
                line.sorted { $0.box.standardized.minX < $1.box.standardized.minX }
                    .map(\.text)
                    .joined(separator: " ")
            }
            .joined(separator: "\n")
    }

    /// Two boxes sit on the same line when they overlap vertically by more than
    /// half the shorter box's height — tolerant of small baseline jitter while
    /// still splitting genuinely stacked lines.
    private static func sameLine(_ a: CGRect, _ b: CGRect) -> Bool {
        let a = a.standardized, b = b.standardized
        let overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        return overlap > 0.5 * min(a.height, b.height)
    }

    /// A line's vertical position for ordering — the average of its words' centres.
    private static func lineMidY(_ line: [OCRObservation]) -> CGFloat {
        let total = line.reduce(CGFloat(0)) { $0 + $1.box.standardized.midY }
        return total / CGFloat(line.count)
    }
}
