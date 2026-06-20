import XCTest
@testable import QuickRunKit

/// The row-matching primitive. Assembly is covered by `ScrollMosaicTests`.
final class ScrollStitcherTests: XCTestCase {
    func testEqualRowsMatchExactly() {
        XCTAssertTrue(ScrollStitcher.rowsMatch([1, 2, 3], [1, 2, 3], tolerance: 0))
        XCTAssertFalse(ScrollStitcher.rowsMatch([1, 2, 3], [1, 2, 4], tolerance: 0))
    }

    func testRowsMatchWithinTolerance() {
        // Real scrolling perturbs every row a little; tolerance absorbs it.
        XCTAssertTrue(ScrollStitcher.rowsMatch([100, 100], [103, 98], tolerance: 5)) // |3| + |2| = 5
        XCTAssertFalse(ScrollStitcher.rowsMatch([100, 100], [110, 100], tolerance: 5)) // |10| > 5
    }

    func testDifferingLengthsNeverMatch() {
        XCTAssertFalse(ScrollStitcher.rowsMatch([100], [100, 100], tolerance: 1000))
    }
}
