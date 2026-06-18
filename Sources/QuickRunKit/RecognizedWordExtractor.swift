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
            line.enumerateSubstrings(in: line.startIndex..<line.endIndex, options: .byWords) { substring, _, _, _ in
                guard let word = substring, isLookupWorthy(word) else { return }
                let key = word.lowercased()
                guard seen.insert(key).inserted else { return }
                result.append(word)
            }
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
