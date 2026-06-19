import XCTest
@testable import QuickRunKit

/// Synthetic pixel sizes — no images — like `ScrollStitcherTests`. A scale of 2
/// (Retina) is used throughout so the point/pixel distinction is exercised.
final class ScrollPreviewLayoutTests: XCTestCase {
    // MARK: - Growing regime (fits)

    func testShortStitchShownAtBoxWidthOneToOne() {
        // 400×600 px at scale 2 → 200×300 pt; available 800 pt → fits.
        let r = ScrollPreviewLayout.layout(
            stitchedPixelSize: CGSize(width: 400, height: 600), scale: 2, availableHeight: 800)
        XCTAssertEqual(r.displaySize, CGSize(width: 200, height: 300))
        XCTAssertFalse(r.isNarrowing)
    }

    func testExactlyFillingHeightStillNotNarrowing() {
        // 200 pt tall stitch, 200 pt available → fits exactly, shown 1:1.
        let r = ScrollPreviewLayout.layout(
            stitchedPixelSize: CGSize(width: 400, height: 400), scale: 2, availableHeight: 200)
        XCTAssertEqual(r.displaySize, CGSize(width: 200, height: 200))
        XCTAssertFalse(r.isNarrowing)
    }

    // MARK: - Narrowing regime (exceeds)

    func testTallStitchClampsHeightAndNarrowsWidth() {
        // 400×1600 px at scale 2 → 200×800 pt; available 400 pt → must narrow.
        let r = ScrollPreviewLayout.layout(
            stitchedPixelSize: CGSize(width: 400, height: 1600), scale: 2, availableHeight: 400)
        XCTAssertTrue(r.isNarrowing)
        XCTAssertEqual(r.displaySize.height, 400, "height clamps to available")
        // factor = 400/800 = 0.5 → width = 200 * 0.5 = 100.
        XCTAssertEqual(r.displaySize.width, 100, accuracy: 0.0001)
    }

    func testScaleIsAvailableOverStitchedHeightWhenNarrowing() {
        // The narrowing scale is exactly availableHeight / stitchHeight(points).
        let pixel = CGSize(width: 600, height: 3000)
        let scale: CGFloat = 3
        let available: CGFloat = 500
        let r = ScrollPreviewLayout.layout(stitchedPixelSize: pixel, scale: scale, availableHeight: available)
        let boxWidth = pixel.width / scale          // 200 pt
        let stitchHeight = pixel.height / scale      // 1000 pt
        let factor = available / stitchHeight        // 0.5
        XCTAssertTrue(r.isNarrowing)
        XCTAssertEqual(r.displaySize.height, available, accuracy: 0.0001)
        XCTAssertEqual(r.displaySize.width, boxWidth * factor, accuracy: 0.0001)
    }

    // MARK: - Invariant across both regimes

    func testDisplayedWidthNeverExceedsBoxWidth() {
        let pixel = CGSize(width: 800, height: 5000)
        let scale: CGFloat = 2
        let boxWidth = pixel.width / scale // 400 pt
        for available in stride(from: CGFloat(50), through: 4000, by: 137) {
            let r = ScrollPreviewLayout.layout(stitchedPixelSize: pixel, scale: scale, availableHeight: available)
            XCTAssertLessThanOrEqual(r.displaySize.width, boxWidth + 0.0001,
                                     "width must never exceed the Main Box width (available=\(available))")
        }
    }

    // MARK: - Degenerate inputs

    func testZeroOrNegativeInputsReturnZero() {
        XCTAssertEqual(ScrollPreviewLayout.layout(
            stitchedPixelSize: CGSize(width: 100, height: 100), scale: 0, availableHeight: 100).displaySize, .zero)
        XCTAssertEqual(ScrollPreviewLayout.layout(
            stitchedPixelSize: CGSize(width: 100, height: 100), scale: 2, availableHeight: 0).displaySize, .zero)
        XCTAssertEqual(ScrollPreviewLayout.layout(
            stitchedPixelSize: CGSize(width: 0, height: 100), scale: 2, availableHeight: 100).displaySize, .zero)
    }
}
