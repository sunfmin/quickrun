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
    /// de-duplicating case-insensitively (keeping the first form seen).
    public static func words(from lines: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for line in lines {
            line.enumerateSubstrings(in: line.startIndex..<line.endIndex, options: .byWords) { substring, _, _, _ in
                guard let word = substring else { return }
                let key = word.lowercased()
                guard !key.isEmpty, seen.insert(key).inserted else { return }
                result.append(word)
            }
        }
        return result
    }
}
