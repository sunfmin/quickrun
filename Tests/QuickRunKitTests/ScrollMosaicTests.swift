import XCTest
@testable import QuickRunKit

/// Frames are arrays of single-element row descriptors `[v]`, one per pixel row —
/// synthetic, no images. Each distinct value stands for a distinct page row, so a
/// page is just an ascending run and the mosaic should reconstruct it however the
/// frames arrive.
final class ScrollMosaicTests: XCTestCase {
    private func frame(_ rows: [UInt8]) -> [[UInt8]] { rows.map { [$0] } }

    /// Exact match, generous search window, grows on any single new row.
    private func mosaic() -> ScrollMosaic {
        ScrollMosaic(tolerance: ScrollStitcher.Tolerance(rowTolerance: 0, minMatchRatio: 1, minOverlap: 2),
                     maxShift: 100, minAdvance: 1)
    }

    /// Read the assembled page back as its scalar rows.
    private func page(_ m: ScrollMosaic) -> [UInt8] { m.canvas.map { $0[0] } }

    func testFirstFrameIsThePage() {
        var m = mosaic()
        XCTAssertTrue(m.add(frame([1, 2, 3, 4])))
        XCTAssertEqual(page(m), [1, 2, 3, 4])
        XCTAssertEqual(m.placements, [0])
    }

    func testScrollingDownGrowsTheBottom() {
        var m = mosaic()
        m.add(frame([1, 2, 3, 4, 5]))
        XCTAssertTrue(m.add(frame([3, 4, 5, 6, 7]))) // overlap [3,4,5]
        XCTAssertEqual(page(m), [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(m.placements, [0, 2])
        XCTAssertEqual(m.height, 7)
    }

    func testScrollingUpGrowsTheTop() {
        var m = mosaic()
        m.add(frame([5, 6, 7, 8, 9, 10]))
        XCTAssertTrue(m.add(frame([1, 2, 3, 4, 5, 6]))) // overlap [5,6] above the top
        XCTAssertEqual(page(m), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
        // The first frame shifted down by the 4 new top rows; the new frame sits at 0.
        XCTAssertEqual(m.placements, [4, 0])
        XCTAssertEqual(m.height, 10)
    }

    func testRepeatedFrameIsDroppedNotDuplicated() {
        var m = mosaic()
        m.add(frame([1, 2, 3, 4]))
        XCTAssertFalse(m.add(frame([1, 2, 3, 4])), "an identical frame adds nothing")
        XCTAssertFalse(m.add(frame([2, 3, 4])), "a frame fully inside the page adds nothing")
        XCTAssertEqual(page(m), [1, 2, 3, 4])
        XCTAssertEqual(m.placements, [0])
    }

    func testFreeUpAndDownEndsAsTheWholePage() {
        var m = mosaic()
        m.add(frame([4, 5, 6, 7]))       // start in the middle
        m.add(frame([6, 7, 8, 9]))       // scroll down
        m.add(frame([1, 2, 3, 4, 5]))    // scroll back up past the start
        m.add(frame([5, 6, 7]))          // wander back into seen content → dropped
        m.add(frame([8, 9, 10, 11]))     // scroll down past the bottom
        XCTAssertEqual(page(m), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11])
        XCTAssertEqual(m.height, 11)
    }

    func testUnalignableFrameIsDropped() {
        var m = mosaic()
        m.add(frame([1, 2, 3, 4]))
        // Disjoint content with no shared band → can't be placed → dropped.
        XCTAssertFalse(m.add(frame([50, 51, 52, 53])))
        XCTAssertEqual(page(m), [1, 2, 3, 4])
    }

    func testAlignmentToleratesPerRowNoise() {
        // Within tolerance the overlap is still found and the page is continuous.
        var m = ScrollMosaic(tolerance: ScrollStitcher.Tolerance(rowTolerance: 4, minMatchRatio: 1, minOverlap: 2),
                             maxShift: 100, minAdvance: 1)
        m.add(frame([10, 20, 30, 40]))
        XCTAssertTrue(m.add(frame([32, 41, 50, 60]))) // [30,40] ≈ [32,41]
        XCTAssertEqual(m.height, 6)
    }

    func testAmbiguousMatchIsDropped() {
        // A repetitive page: the band [1,2] matches at two distinct places, so a
        // frame that is only that band is too ambiguous to place — dropping it
        // beats guessing and stitching in already-captured content.
        var m = mosaic()
        m.add(frame([1, 2, 3, 1, 2, 3]))
        XCTAssertFalse(m.add(frame([1, 2])))
        XCTAssertEqual(page(m), [1, 2, 3, 1, 2, 3])
    }

    func testStrongerEvidenceWinsOverAWeakerFalseMatch() {
        // The band [5,6,7,8] matches strongly (4 rows) at one place and only weakly
        // (the lone repeated [5]) elsewhere — the strong, unique alignment is taken,
        // extending the page by the new row.
        var m = ScrollMosaic(tolerance: ScrollStitcher.Tolerance(rowTolerance: 0, minMatchRatio: 1, minOverlap: 2),
                             maxShift: 100, minAdvance: 1)
        m.add(frame([5, 1, 2, 3, 4, 5, 6, 7, 8]))
        XCTAssertTrue(m.add(frame([5, 6, 7, 8, 9])))
        XCTAssertEqual(page(m), [5, 1, 2, 3, 4, 5, 6, 7, 8, 9])
    }

    func testViewportIsTrackedAcrossDroppedFrames() {
        // After scrolling down then idling (dropped repeats), the search anchor
        // stays with the viewport, so the next downward frame still aligns.
        var m = mosaic()
        m.add(frame([1, 2, 3, 4]))
        m.add(frame([2, 3, 4, 5]))      // down one
        XCTAssertFalse(m.add(frame([2, 3, 4, 5]))) // idle repeat, dropped, anchor tracked
        XCTAssertTrue(m.add(frame([3, 4, 5, 6])))  // down one more, still aligns
        XCTAssertEqual(page(m), [1, 2, 3, 4, 5, 6])
    }
}
