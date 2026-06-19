import CoreGraphics
import Foundation

/// Which Markup tool is active. Grows with the toolset in later slices.
public enum MarkupTool: Equatable {
    case select
    case rectangle
    case ellipse
    case arrow
    case text
    case freehand
    case highlight
    case blur
}

/// An action the Editor's glue should perform, decided by the pure view model.
public enum EditorIntent: Equatable {
    case lookUp(String)
    case copyToClipboard
    /// Put the Capture's full recognized text (reading order) on the clipboard.
    case copyText(String)
    case saveToFile
}

/// Drives the Editor's pure state: the Recognized words, the active tool, the
/// current object selection, and the Markup document (with its undo/redo).
public final class EditorViewModel {
    public private(set) var recognizedWords: [String]
    /// The Capture's full recognized text in reading order, for Copy-text. Kept
    /// apart from `recognizedWords` (which is de-duplicated for the lookup list).
    public private(set) var recognizedText: String
    public let document: MarkupDocument
    public private(set) var currentTool: MarkupTool
    public private(set) var selectedObjectID: UUID?
    /// Style applied to newly drawn objects (and to the selection when restyled).
    public private(set) var defaultStyle: MarkupStyle

    public init(recognizedWords: [String] = [], document: MarkupDocument = MarkupDocument()) {
        self.recognizedWords = recognizedWords
        self.recognizedText = ""
        self.document = document
        self.currentTool = .select
        self.selectedObjectID = nil
        self.defaultStyle = MarkupStyle()
    }

    // MARK: - Recognized words

    /// Replace the Recognized words once OCR finishes, without disturbing the
    /// Markup document the user may already be editing.
    public func setRecognizedWords(_ words: [String]) {
        recognizedWords = words
    }

    /// Replace the full reading-order text once OCR finishes (Copy-text source).
    public func setRecognizedText(_ text: String) {
        recognizedText = text
    }

    /// The Query to look up for the word at `index`, or `nil` if out of range.
    public func query(forWordAt index: Int) -> String? {
        guard recognizedWords.indices.contains(index) else { return nil }
        return recognizedWords[index]
    }

    /// Intent for picking the word at `index`, or `nil` if out of range.
    public func selectWord(at index: Int) -> EditorIntent? {
        query(forWordAt: index).map { .lookUp($0) }
    }

    // MARK: - Tool & selection

    public func selectTool(_ tool: MarkupTool) {
        currentTool = tool
        if tool != .select { selectedObjectID = nil } // drawing clears any selection
    }

    public func select(objectID: UUID?) {
        selectedObjectID = objectID
    }

    // MARK: - Editing (delegates to the document, keeps selection coherent)

    /// Add `object` and select it.
    public func addObject(_ object: MarkupObject) {
        document.add(object)
        selectedObjectID = object.id
    }

    public func deleteSelection() {
        guard let id = selectedObjectID else { return }
        document.remove(id: id)
        selectedObjectID = nil
    }

    public func moveSelection(by offset: CGSize) {
        guard let id = selectedObjectID else { return }
        document.move(id: id, by: offset)
    }

    /// Apply `style` to the selection if there is one, and remember it as the
    /// style for future objects.
    public func setStyle(_ style: MarkupStyle) {
        defaultStyle = style
        guard let id = selectedObjectID,
              var object = document.objects.first(where: { $0.id == id }) else { return }
        object.style = style
        document.update(object)
    }

    public func undo() {
        document.undo()
        reconcileSelection()
    }

    public func redo() {
        document.redo()
        reconcileSelection()
    }

    // MARK: - Export

    public func copy() -> EditorIntent { .copyToClipboard }

    /// Copy the full recognized text. The glue beeps when the string is empty
    /// (nothing was recognized) rather than clearing the clipboard.
    public func copyText() -> EditorIntent { .copyText(recognizedText) }

    public func save() -> EditorIntent { .saveToFile }

    // MARK: -

    /// Drop the selection if undo/redo removed the selected object.
    private func reconcileSelection() {
        if let id = selectedObjectID, !document.objects.contains(where: { $0.id == id }) {
            selectedObjectID = nil
        }
    }
}
