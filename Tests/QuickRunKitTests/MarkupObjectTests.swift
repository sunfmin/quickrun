import XCTest
import CoreGraphics
@testable import QuickRunKit

final class MarkupObjectTests: XCTestCase {
    private func object(_ kind: MarkupObject.Kind, lineWidth: Double = 0) -> MarkupObject {
        MarkupObject(kind: kind, style: MarkupStyle(lineWidth: lineWidth))
    }

    // MARK: - translated(by:)

    func testRectangleTranslates() {
        let moved = object(.rectangle(CGRect(x: 1, y: 2, width: 3, height: 4)))
            .translated(by: CGSize(width: 5, height: 6))
        XCTAssertEqual(moved.kind, .rectangle(CGRect(x: 6, y: 8, width: 3, height: 4)))
    }

    func testEllipseTranslates() {
        let moved = object(.ellipse(CGRect(x: 1, y: 2, width: 3, height: 4)))
            .translated(by: CGSize(width: 5, height: 6))
        XCTAssertEqual(moved.kind, .ellipse(CGRect(x: 6, y: 8, width: 3, height: 4)))
    }

    func testArrowTranslates() {
        let moved = object(.arrow(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 10, y: 10)))
            .translated(by: CGSize(width: 5, height: 3))
        XCTAssertEqual(moved.kind, .arrow(from: CGPoint(x: 5, y: 3), to: CGPoint(x: 15, y: 13)))
    }

    func testTextTranslates() {
        let moved = object(.text("hi", CGRect(x: 0, y: 0, width: 10, height: 10)))
            .translated(by: CGSize(width: 2, height: 4))
        XCTAssertEqual(moved.kind, .text("hi", CGRect(x: 2, y: 4, width: 10, height: 10)))
    }

    func testEmojiTranslates() {
        let moved = object(.emoji("👍", CGRect(x: 1, y: 2, width: 10, height: 10)))
            .translated(by: CGSize(width: 3, height: 4))
        XCTAssertEqual(moved.kind, .emoji("👍", CGRect(x: 4, y: 6, width: 10, height: 10)))
    }

    func testFreehandTranslatesEveryPoint() {
        let moved = object(.freehand([CGPoint(x: 0, y: 0), CGPoint(x: 2, y: 2)]))
            .translated(by: CGSize(width: 1, height: 1))
        XCTAssertEqual(moved.kind, .freehand([CGPoint(x: 1, y: 1), CGPoint(x: 3, y: 3)]))
    }

    func testHighlightTranslatesEveryPoint() {
        let moved = object(.highlight([CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 0)]))
            .translated(by: CGSize(width: 0, height: 5))
        XCTAssertEqual(moved.kind, .highlight([CGPoint(x: 0, y: 5), CGPoint(x: 4, y: 5)]))
    }

    func testBlurTranslates() {
        let moved = object(.blur(CGRect(x: 1, y: 1, width: 6, height: 4)))
            .translated(by: CGSize(width: 3, height: 2))
        XCTAssertEqual(moved.kind, .blur(CGRect(x: 4, y: 3, width: 6, height: 4)))
    }

    func testBlurBoundsAreItsRect() {
        let bounds = object(.blur(CGRect(x: 2, y: 3, width: 10, height: 5)), lineWidth: 0).bounds
        XCTAssertEqual(bounds, CGRect(x: 2, y: 3, width: 10, height: 5))
    }

    // MARK: - bounds

    func testArrowBoundsSpanEndpoints() {
        let bounds = object(.arrow(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 10, y: 4)), lineWidth: 0).bounds
        XCTAssertEqual(bounds, CGRect(x: 0, y: 0, width: 10, height: 4))
    }

    func testFreehandBoundsContainAllPoints() {
        let bounds = object(.freehand([CGPoint(x: 2, y: 3), CGPoint(x: 8, y: 1), CGPoint(x: 5, y: 9)]), lineWidth: 0).bounds
        XCTAssertEqual(bounds, CGRect(x: 2, y: 1, width: 6, height: 8))
    }

    func testTextBoundsAreItsFrame() {
        let bounds = object(.text("hi", CGRect(x: 4, y: 5, width: 20, height: 12))).bounds
        XCTAssertEqual(bounds, CGRect(x: 4, y: 5, width: 20, height: 12))
    }

    func testEmojiBoundsAreItsFrame() {
        let bounds = object(.emoji("🔥", CGRect(x: 4, y: 5, width: 20, height: 12))).bounds
        XCTAssertEqual(bounds, CGRect(x: 4, y: 5, width: 20, height: 12))
    }

    func testLineWidthOutsetsBounds() {
        let bounds = object(.rectangle(CGRect(x: 10, y: 10, width: 10, height: 10)), lineWidth: 4).bounds
        XCTAssertEqual(bounds, CGRect(x: 8, y: 8, width: 14, height: 14))
    }

    func testEllipseBoundsAreItsRectOutsetByLineWidth() {
        let bounds = object(.ellipse(CGRect(x: 10, y: 10, width: 10, height: 10)), lineWidth: 4).bounds
        XCTAssertEqual(bounds, CGRect(x: 8, y: 8, width: 14, height: 14))
    }

    // MARK: - resized(to:)

    func testTextResizesKeepingStringAndFontSize() {
        let original = MarkupObject(kind: .text("hi", CGRect(x: 0, y: 0, width: 10, height: 10)),
                                    style: MarkupStyle(fontSize: 28))
        let resized = original.resized(to: CGRect(x: 4, y: 5, width: 60, height: 40))
        // The frame changes; the string and the font size are untouched.
        XCTAssertEqual(resized.kind, .text("hi", CGRect(x: 4, y: 5, width: 60, height: 40)))
        XCTAssertEqual(resized.style.fontSize, 28)
    }

    func testResizeNormalizesNegativeSize() {
        let resized = object(.rectangle(.zero)).resized(to: CGRect(x: 10, y: 10, width: -6, height: -4))
        XCTAssertEqual(resized.kind, .rectangle(CGRect(x: 4, y: 6, width: 6, height: 4)))
    }

    func testPointBasedKindsAreUnchangedByResize() {
        let arrow = object(.arrow(from: .zero, to: CGPoint(x: 10, y: 10)))
        XCTAssertEqual(arrow.resized(to: CGRect(x: 1, y: 1, width: 50, height: 50)).kind, arrow.kind)
    }

    // MARK: - isResizable

    func testOnlyTextIsResizable() {
        XCTAssertTrue(object(.text("hi", CGRect(x: 0, y: 0, width: 10, height: 10))).isResizable)
        XCTAssertFalse(object(.emoji("🔥", CGRect(x: 0, y: 0, width: 10, height: 10))).isResizable)
        XCTAssertFalse(object(.rectangle(CGRect(x: 0, y: 0, width: 10, height: 10))).isResizable)
    }
}
