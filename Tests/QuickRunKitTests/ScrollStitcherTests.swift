import XCTest
@testable import QuickRunKit

/// Row signatures are just `[UInt64]` here — synthetic, no images — exactly how
/// `ClickableWordsTests` fakes OCR. Each number stands for one pixel row.
final class ScrollStitcherTests: XCTestCase {
    // MARK: - verticalOverlap

    func testExactOverlapIsTheSharedRun() {
        // a's bottom [3,4,5] == b's top [3,4,5]
        XCTAssertEqual(ScrollStitcher.verticalOverlap(between: [1, 2, 3, 4, 5], [3, 4, 5, 6, 7]), 3)
    }

    func testNoOverlapIsZero() {
        XCTAssertEqual(ScrollStitcher.verticalOverlap(between: [1, 2, 3], [4, 5, 6]), 0)
    }

    func testPartialOverlap() {
        XCTAssertEqual(ScrollStitcher.verticalOverlap(between: [1, 2, 3, 4, 5], [4, 5, 6, 7, 8]), 2)
    }

    func testIdenticalFramesOverlapFully() {
        XCTAssertEqual(ScrollStitcher.verticalOverlap(between: [1, 2, 3], [1, 2, 3]), 3)
    }

    func testSingleRowScrollLeavesNearlyFullOverlap() {
        // Scrolled by one row: overlap is height - 1.
        XCTAssertEqual(ScrollStitcher.verticalOverlap(between: [1, 2, 3, 4], [2, 3, 4, 5]), 3)
    }

    func testGreedyMatchIgnoresAnInnerCoincidence() {
        // A '5' appears mid-frame in b, but the genuine seam is the suffix/prefix
        // run [4,5] — the largest match wins.
        XCTAssertEqual(ScrollStitcher.verticalOverlap(between: [1, 2, 3, 4, 5], [4, 5, 9, 5, 0]), 2)
    }

    // MARK: - offsets / height

    func testOffsetsStackFramesWithOverlapsRemoved() {
        let frames: [[UInt64]] = [[1, 2, 3, 4, 5], [3, 4, 5, 6, 7], [6, 7, 8, 9, 10]]
        // ov(0,1)=3 → offset1 = 5-3 = 2; ov(1,2)=2 → offset2 = 2 + (5-2) = 5.
        XCTAssertEqual(ScrollStitcher.offsets(forFrames: frames), [0, 2, 5])
        // Stitched height spans [1...10].
        XCTAssertEqual(ScrollStitcher.stitchedHeight(forFrames: frames), 10)
    }

    func testNonOverlappingFramesStackEndToEnd() {
        let frames: [[UInt64]] = [[1, 2, 3], [4, 5, 6]]
        XCTAssertEqual(ScrollStitcher.offsets(forFrames: frames), [0, 3])
        XCTAssertEqual(ScrollStitcher.stitchedHeight(forFrames: frames), 6)
    }

    func testSingleFrameIsItsOwnHeightAtZero() {
        XCTAssertEqual(ScrollStitcher.offsets(forFrames: [[1, 2, 3, 4]]), [0])
        XCTAssertEqual(ScrollStitcher.stitchedHeight(forFrames: [[1, 2, 3, 4]]), 4)
    }

    func testNoFramesIsEmpty() {
        XCTAssertEqual(ScrollStitcher.offsets(forFrames: []), [])
        XCTAssertEqual(ScrollStitcher.stitchedHeight(forFrames: []), 0)
    }

    // MARK: - end of scroll

    func testReachedEndWhenFrameAddsNothing() {
        XCTAssertTrue(ScrollStitcher.reachedEnd([1, 2, 3, 4], [1, 2, 3, 4]))
    }

    func testNotReachedEndWhileStillScrolling() {
        XCTAssertFalse(ScrollStitcher.reachedEnd([1, 2, 3, 4], [2, 3, 4, 5]))
        XCTAssertFalse(ScrollStitcher.reachedEnd([], []))
    }
}
