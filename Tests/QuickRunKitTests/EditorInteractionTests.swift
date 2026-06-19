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
        marks: [MarkupObject] = []
    ) -> EditorInteraction {
        EditorInteraction.resolve(tool: tool, point: point, region: region,
                                  handleTolerance: 12, wordRects: words, marks: marks)
    }

    private func mark(_ rect: CGRect) -> MarkupObject {
        MarkupObject(kind: .rectangle(rect), style: MarkupStyle(lineWidth: 0))
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
}
