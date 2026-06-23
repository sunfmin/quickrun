import XCTest
import CoreGraphics
@testable import QuickRunKit

final class EditorInteractionTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    // A committed region with room around the edges so interior points miss the
    // handles (tolerance 12).
    private var region: RegionSelection {
        RegionSelection(bounds: bounds, rect: CGRect(x: 200, y: 200, width: 400, height: 300))
    }

    private func resolve(
        tool: MarkupTool = .select,
        at point: CGPoint,
        words: [CGRect] = [],
        marks: [MarkupObject] = [],
        selectedMark: MarkupObject? = nil
    ) -> EditorInteraction {
        EditorInteraction.resolve(tool: tool, point: point, region: region,
                                  handleTolerance: 12, wordRects: words, marks: marks,
                                  selectedMark: selectedMark)
    }

    private func mark(_ rect: CGRect) -> MarkupObject {
        MarkupObject(kind: .rectangle(rect), style: MarkupStyle(lineWidth: 0))
    }

    private func textMark(_ rect: CGRect) -> MarkupObject {
        MarkupObject(kind: .text("hi", rect), style: MarkupStyle(lineWidth: 0))
    }

    // MARK: - Handle wins over everything beneath it (the overlap case)

    func testResizeHandleBeatsAWordAndMarkUnderIt() {
        // A corner handle at the region's top-left (200, 500), with both a word
        // and a mark sitting right on it. The handle must still win.
        let corner = CGPoint(x: 200, y: 500)
        let onCorner = CGRect(x: 190, y: 490, width: 20, height: 20)
        let result = resolve(at: corner, words: [onCorner], marks: [mark(onCorner)])
        XCTAssertEqual(result, .resizeRegion(.topLeft))
    }

    // MARK: - A selected text label's resize handles

    func testSelectedTextHandleResizesIt() {
        let text = textMark(CGRect(x: 350, y: 320, width: 100, height: 80))
        // The top-left corner of the text frame, with the label selected.
        let result = resolve(at: CGPoint(x: 350, y: 400), marks: [text], selectedMark: text)
        XCTAssertEqual(result, .resizeMark(text.id, .topLeft))
    }

    func testSelectedTextHandleBeatsRegionHandleBeneathIt() {
        // The label's bottom-left handle sits exactly on the region's own corner
        // handle (200, 200); the selected label's handle must still win.
        let text = textMark(CGRect(x: 200, y: 200, width: 100, height: 80))
        XCTAssertEqual(resolve(at: CGPoint(x: 200, y: 200), marks: [text], selectedMark: text),
                       .resizeMark(text.id, .bottomLeft))
    }

    func testTextHandleIgnoredWhenLabelNotSelected() {
        // Same corner, but nothing is selected: there are no handles to grab, so
        // the click is just empty interior space and moves the region.
        let text = textMark(CGRect(x: 350, y: 320, width: 100, height: 80))
        XCTAssertEqual(resolve(at: CGPoint(x: 350, y: 400), marks: [text]), .moveRegion)
    }

    func testNonTextSelectionHasNoResizeHandles() {
        // A selected rectangle is not resizable, so its corner stays plain interior.
        let box = mark(CGRect(x: 350, y: 320, width: 100, height: 80))
        XCTAssertEqual(resolve(at: CGPoint(x: 350, y: 400), marks: [box], selectedMark: box), .moveRegion)
    }

    // MARK: - Word beats a mark beneath it

    func testWordBeatsAMarkUnderIt() {
        let point = CGPoint(x: 400, y: 350) // interior, clear of handles
        let overlap = CGRect(x: 380, y: 330, width: 40, height: 40)
        XCTAssertEqual(resolve(at: point, words: [overlap], marks: [mark(overlap)]), .lookUpWord(0))
    }

    func testTopmostWordWins() {
        let point = CGPoint(x: 400, y: 350)
        let lower = CGRect(x: 380, y: 330, width: 40, height: 40)
        let upper = CGRect(x: 390, y: 340, width: 30, height: 30)
        // Both contain the point; the later (topmost) one is chosen.
        XCTAssertEqual(resolve(at: point, words: [lower, upper]), .lookUpWord(1))
    }

    // MARK: - Mark, region, deselect

    func testTopmostMarkSelectedWhenNoWord() {
        let point = CGPoint(x: 400, y: 350)
        let lower = mark(CGRect(x: 380, y: 330, width: 40, height: 40))
        let upper = mark(CGRect(x: 390, y: 340, width: 30, height: 30))
        XCTAssertEqual(resolve(at: point, marks: [lower, upper]), .selectMark(upper.id))
    }

    func testEmptySpaceInsideRegionMovesRegion() {
        XCTAssertEqual(resolve(at: CGPoint(x: 400, y: 350)), .moveRegion)
    }

    func testEmptySpaceOutsideRegionDeselects() {
        XCTAssertEqual(resolve(at: CGPoint(x: 800, y: 700)), .deselect)
    }

    // MARK: - Drawing tools skip handle/word/mark resolution

    func testDrawingToolDrawsEvenOverAHandle() {
        let corner = CGPoint(x: 200, y: 500)
        let onCorner = CGRect(x: 190, y: 490, width: 20, height: 20)
        XCTAssertEqual(resolve(tool: .rectangle, at: corner, words: [onCorner], marks: [mark(onCorner)]), .drawMarkup)
    }

    func testEveryDrawingToolResolvesToDraw() {
        for tool in [MarkupTool.rectangle, .ellipse, .arrow, .freehand, .highlight, .blur] {
            XCTAssertEqual(resolve(tool: tool, at: CGPoint(x: 400, y: 350)), .drawMarkup, "\(tool)")
        }
    }

    func testTextToolBeginsText() {
        XCTAssertEqual(resolve(tool: .text, at: CGPoint(x: 400, y: 350)), .beginText)
    }

    func testEmojiToolPlacesEmoji() {
        XCTAssertEqual(resolve(tool: .emoji, at: CGPoint(x: 400, y: 350)), .placeEmoji)
    }
}
