import Foundation

/// Drives the Editor's pure state. For now it owns the Recognized words and
/// answers which Query a given word produces; later slices grow it to hold the
/// Markup document and the copy/save intents.
public final class EditorViewModel {
    public private(set) var recognizedWords: [String]

    public init(recognizedWords: [String] = []) {
        self.recognizedWords = recognizedWords
    }

    /// The Query to look up for the word at `index`, or `nil` if out of range.
    public func query(forWordAt index: Int) -> String? {
        guard recognizedWords.indices.contains(index) else { return nil }
        return recognizedWords[index]
    }
}
