import XCTest
import CoreGraphics
@testable import QuickRunKit

final class RegionSelectionTests: XCTestCase {
    private let display = CGRect(x: 0, y: 0, width: 1000, height: 800)

    // MARK: - Normalization (any drag direction → same rectangle)

    func testDragNormalizesAcrossAllDirections() {
        let a = CGPoint(x: 200, y: 150)
        let b = CGPoint(x: 600, y: 500)
        let expected = CGRect(x: 200, y: 150, width: 400, height: 350)

        // Dragging from any of the four corners must produce the same region.
        for (start, end) in [(a, b),
                             (b, a),
                             (CGPoint(x: b.x, y: a.y), CGPoint(x: a.x, y: b.y)),
                             (CGPoint(x: a.x, y: b.y), CGPoint(x: b.x, y: a.y))] {
            let region = RegionSelection.fromDrag(from: start, to: end, in: display)
            XCTAssertEqual(region.rect, expected)
        }
    }

    // MARK: - Clamping to the display

    func testDragBeyondBoundsIsClamped() {
        let region = RegionSelection.fromDrag(
            from: CGPoint(x: -50, y: -100),
            to: CGPoint(x: 1200, y: 900),
            in: display
        )
        XCTAssertEqual(region.rect, display)
    }

    func testDragPartlyOutsideKeepsTheInsidePortion() {
        let region = RegionSelection.fromDrag(
            from: CGPoint(x: 900, y: 700),
            to: CGPoint(x: 1300, y: 1100),
            in: display
        )
        XCTAssertEqual(region.rect, CGRect(x: 900, y: 700, width: 100, height: 100))
    }

    func testInitClampsAGivenRect() {
        let region = RegionSelection(bounds: display, rect: CGRect(x: 500, y: 400, width: 800, height: 800))
        XCTAssertEqual(region.rect, CGRect(x: 500, y: 400, width: 500, height: 400))
    }

    // MARK: - Zero / tiny drags

    func testZeroDragIsEmpty() {
        let region = RegionSelection.fromDrag(from: CGPoint(x: 300, y: 300),
                                              to: CGPoint(x: 300, y: 300), in: display)
        XCTAssertTrue(region.isEmpty)
        XCTAssertEqual(region.rect, CGRect(x: 300, y: 300, width: 0, height: 0))
    }

    func testTinyDragBelowMinIsEmpty() {
        let region = RegionSelection.fromDrag(from: CGPoint(x: 100, y: 100),
                                              to: CGPoint(x: 104, y: 130), in: display)
        XCTAssertTrue(region.isEmpty, "width below minSize counts as empty even when height is large")
    }

    func testDealtAtLeastMinSizeInBothAxesIsNotEmpty() {
        let region = RegionSelection.fromDrag(from: CGPoint(x: 100, y: 100),
                                              to: CGPoint(x: 100 + RegionSelection.minSize, y: 100 + RegionSelection.minSize),
                                              in: display)
        XCTAssertFalse(region.isEmpty)
    }

    // MARK: - Handles

    private func region(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> RegionSelection {
        RegionSelection(bounds: display, rect: CGRect(x: x, y: y, width: w, height: h))
    }

    func testHandlePointsSitAtCornersAndEdgeMidpoints() {
        let r = region(100, 200, 400, 300) // minX 100, maxX 500, minY 200, maxY 500
        XCTAssertEqual(r.handlePoint(.topLeft), CGPoint(x: 100, y: 500))
        XCTAssertEqual(r.handlePoint(.topRight), CGPoint(x: 500, y: 500))
        XCTAssertEqual(r.handlePoint(.bottomLeft), CGPoint(x: 100, y: 200))
        XCTAssertEqual(r.handlePoint(.bottomRight), CGPoint(x: 500, y: 200))
        XCTAssertEqual(r.handlePoint(.top), CGPoint(x: 300, y: 500))
        XCTAssertEqual(r.handlePoint(.bottom), CGPoint(x: 300, y: 200))
        XCTAssertEqual(r.handlePoint(.left), CGPoint(x: 100, y: 350))
        XCTAssertEqual(r.handlePoint(.right), CGPoint(x: 500, y: 350))
    }

    func testHitTestPicksTheHandleUnderThePoint() {
        let r = region(100, 200, 400, 300)
        XCTAssertEqual(r.handle(at: CGPoint(x: 103, y: 503), tolerance: 10), .topLeft)
        XCTAssertNil(r.handle(at: CGPoint(x: 300, y: 350), tolerance: 10), "interior point hits no handle")
    }

    func testResizeFromEachHandleMovesOnlyItsEdges() {
        let r = region(100, 100, 400, 400) // minX100 maxX500 minY100 maxY500

        // Each handle dragged by (+50,+50); only the edges it owns should move.
        XCTAssertEqual(r.resized(.left, to: CGPoint(x: 150, y: 350)).rect,
                       CGRect(x: 150, y: 100, width: 350, height: 400))
        XCTAssertEqual(r.resized(.right, to: CGPoint(x: 550, y: 350)).rect,
                       CGRect(x: 100, y: 100, width: 450, height: 400))
        XCTAssertEqual(r.resized(.bottom, to: CGPoint(x: 300, y: 150)).rect,
                       CGRect(x: 100, y: 150, width: 400, height: 350))
        XCTAssertEqual(r.resized(.top, to: CGPoint(x: 300, y: 550)).rect,
                       CGRect(x: 100, y: 100, width: 400, height: 450))
        XCTAssertEqual(r.resized(.topRight, to: CGPoint(x: 600, y: 600)).rect,
                       CGRect(x: 100, y: 100, width: 500, height: 500))
    }

    func testResizeClampsToBounds() {
        let r = region(100, 100, 400, 400)
        // Drag the top-right corner past the display edge.
        XCTAssertEqual(r.resized(.topRight, to: CGPoint(x: 5000, y: 5000)).rect,
                       CGRect(x: 100, y: 100, width: 900, height: 700))
    }

    func testResizeHonoursMinimumSize() {
        let r = region(100, 100, 400, 400)
        // Drag the left edge way past the right edge: it stops minSize short.
        let resized = r.resized(.left, to: CGPoint(x: 900, y: 300)).rect
        XCTAssertEqual(resized.maxX, 500)
        XCTAssertEqual(resized.minX, 500 - RegionSelection.minSize)
        XCTAssertEqual(resized.width, RegionSelection.minSize)
    }

    func testMoveTranslatesWithinBounds() {
        let r = region(100, 100, 200, 200)
        XCTAssertEqual(r.moved(by: CGSize(width: 50, height: -30)).rect,
                       CGRect(x: 150, y: 70, width: 200, height: 200))
    }

    func testMoveClampsToBoundsKeepingSize() {
        let r = region(100, 100, 200, 200)
        // Shove far past the top-right; the region slides to the corner, same size.
        let moved = r.moved(by: CGSize(width: 5000, height: 5000)).rect
        XCTAssertEqual(moved.size, CGSize(width: 200, height: 200))
        XCTAssertEqual(moved, CGRect(x: 800, y: 600, width: 200, height: 200))
    }
}
