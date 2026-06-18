import Foundation

/// Turns the lines OCR found in a Capture into the ordered list of distinct
/// Recognized words shown in the Editor.
///
/// Words are split on ICU word boundaries (`enumerateSubstrings(.byWords)`) —
/// the same segmentation behind double-click-to-select-word — so English splits
/// on whitespace/punctuation (keeping contractions like "don't" whole) and CJK
/// runs, which have no spaces, are segmented by ICU's built-in dictionary.
public enum RecognizedWordExtractor {
    /// Extract distinct words from `lines`, preserving first-seen order and
    /// de-duplicating case-insensitively (keeping the first form seen). OCR
    /// specks — pure numbers and lone Latin letters like a stray "h" — are
    /// dropped, since they are never what someone wants to look up; single CJK
    /// characters are kept, because each is a real word.
    public static func words(from lines: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for line in lines {
            for segment in segments(in: line) {
                guard isLookupWorthy(segment.text) else { continue }
                let key = segment.text.lowercased()
                guard seen.insert(key).inserted else { continue }
                result.append(segment.text)
            }
        }
        return result
    }

    /// Split a recognized line into lookup-candidate words and their ranges.
    ///
    /// ICU word boundaries do the base segmentation, so CJK is segmented by
    /// dictionary and English splits on whitespace and most punctuation. ICU
    /// keeps a few symbols *inside* a word, though — a period (`QuickRun.app`)
    /// and an underscore (`foo_bar`) — which for a screen full of file names and
    /// directory paths fuses words that should be separately selectable. So each
    /// ICU word is split again on any in-word character that isn't a letter,
    /// digit, or apostrophe: `QuickRun.app` → `QuickRun`, `app`; `foo_bar` →
    /// `foo`, `bar`; while contractions like `don't` stay whole. Each segment
    /// carries its range so the caller can recover its on-image box.
    public static func segments(in line: String) -> [(text: String, range: Range<String.Index>)] {
        var result: [(text: String, range: Range<String.Index>)] = []
        line.enumerateSubstrings(in: line.startIndex..<line.endIndex, options: .byWords) { substring, range, _, _ in
            guard substring != nil else { return }
            var runStart: String.Index?
            var index = range.lowerBound
            while index < range.upperBound {
                if isWordCharacter(line[index]) {
                    if runStart == nil { runStart = index }
                } else if let start = runStart {
                    result.append((String(line[start..<index]), start..<index))
                    runStart = nil
                }
                index = line.index(after: index)
            }
            if let start = runStart {
                result.append((String(line[start..<range.upperBound]), start..<range.upperBound))
            }
        }
        return result
    }

    /// A character that belongs inside a word: a letter (including CJK), a digit,
    /// or an apostrophe (so contractions aren't broken). Everything else —
    /// `. _ / : @` and friends — separates words.
    private static func isWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "'" || $0 == "\u{2019}"
        }
    }

    /// The on-image box for the word at `range` of `line`, derived as a
    /// character-proportional slice of the line's box `lineBox` (normalized,
    /// bottom-left origin). OCR engines often report a box per line but not per
    /// sub-word, so slicing by character position gives every word a distinct,
    /// non-overlapping box — without it, a path's segments and adjacent CJK
    /// words share one box and their highlights merge into a block. CJK
    /// ideographs count double, matching their rendered width, so mixed
    /// CJK/Latin lines slice closer to reality.
    public static func wordBox(in lineBox: CGRect, line: String, range: Range<String.Index>) -> CGRect {
        let widths = line.map(characterWidth)
        let total = widths.reduce(0, +)
        guard total > 0 else { return lineBox }
        let startOffset = line.distance(from: line.startIndex, to: range.lowerBound)
        let endOffset = line.distance(from: line.startIndex, to: range.upperBound)
        let before = widths[0..<startOffset].reduce(0, +)
        let span = widths[startOffset..<endOffset].reduce(0, +)
        return CGRect(x: lineBox.minX + before / total * lineBox.width,
                      y: lineBox.minY,
                      width: span / total * lineBox.width,
                      height: lineBox.height)
    }

    private static func characterWidth(_ character: Character) -> CGFloat {
        character.unicodeScalars.contains(where: isCJK) ? 2 : 1
    }

    /// Turn word-level OCR observations into the clickable Recognized words drawn
    /// on the Capture, keeping each word's box. The same noise filter as
    /// `words(from:)` decides which become clickable — pure numbers and lone
    /// Latin letters are dropped, single CJK characters are kept. Unlike the
    /// sidebar's `words(from:)`, occurrences are NOT de-duplicated: every place a
    /// word appears on the Capture is its own clickable hit area. Whitespace-only
    /// observations are ignored.
    public static func clickableWords(from observations: [OCRObservation]) -> [RecognizedWord] {
        var result: [RecognizedWord] = []
        for observation in observations {
            let word = observation.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isLookupWorthy(word) else { continue }
            result.append(RecognizedWord(text: word, box: observation.box))
        }
        return result
    }

    private static func isLookupWorthy(_ word: String) -> Bool {
        // Must contain a letter — drops pure numbers and stray punctuation.
        guard word.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else {
            return false
        }
        // A lone character is worth keeping only if it is CJK (a real word);
        // a single Latin letter is almost always an OCR speck.
        if word.count == 1 {
            return word.unicodeScalars.allSatisfy(isCJK)
        }
        return true
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x4E00...0x9FFF,   // CJK Unified Ideographs
             0x3400...0x4DBF,   // Extension A
             0xF900...0xFAFF,   // Compatibility Ideographs
             0x3040...0x30FF:   // Hiragana + Katakana
            return true
        default:
            return false
        }
    }
}
