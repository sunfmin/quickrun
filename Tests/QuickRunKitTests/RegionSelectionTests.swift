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
}
