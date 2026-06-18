import XCTest
import CoreGraphics
@testable import QuickRunKit

final class CaptureGeometryTests: XCTestCase {

    // MARK: - View points → image pixels (Y-flip + Retina scale)

    func testPixelRectFlipsYAndScales() {
        // 1000×800-pt overlay on a 2× Retina display. A region whose top is at
        // y=500 (bottom-left) maps to a top-left pixel y of (800 − 500)·2 = 600.
        let region = CGRect(x: 100, y: 200, width: 400, height: 300)
        let pixels = CaptureGeometry.pixelRect(forViewRect: region, viewHeight: 800, scale: 2)
        XCTAssertEqual(pixels, CGRect(x: 200, y: 600, width: 800, height: 600))
    }

    func testPixelRectAtScaleOneOnlyFlipsY() {
        let region = CGRect(x: 0, y: 0, width: 100, height: 100)
        let pixels = CaptureGeometry.pixelRect(forViewRect: region, viewHeight: 800, scale: 1)
        // Bottom-left region → its top edge (maxY=100) becomes pixel y = 700.
        XCTAssertEqual(pixels, CGRect(x: 0, y: 700, width: 100, height: 100))
    }

    func testRegionFillingTheDisplayMapsToTheWholeImage() {
        let full = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let pixels = CaptureGeometry.pixelRect(forViewRect: full, viewHeight: 800, scale: 2)
        XCTAssertEqual(pixels, CGRect(x: 0, y: 0, width: 2000, height: 1600))
    }

    // MARK: - Normalized OCR box → view rect within the region

    func testNormalizedBoxPlacedInsideRegion() {
        let region = CGRect(x: 100, y: 200, width: 400, height: 300)
        let box = CGRect(x: 0.5, y: 0.5, width: 0.25, height: 0.1)
        let rect = CaptureGeometry.viewRect(forNormalizedBox: box, in: region)
        XCTAssertEqual(rect, CGRect(x: 300, y: 350, width: 100, height: 30))
    }

    func testFullNormalizedBoxCoversTheRegion() {
        let region = CGRect(x: 100, y: 200, width: 400, height: 300)
        let rect = CaptureGeometry.viewRect(forNormalizedBox: CGRect(x: 0, y: 0, width: 1, height: 1), in: region)
        XCTAssertEqual(rect, region)
    }

    // MARK: - Round trip

    func testNormalizedBoxRoundTripsThroughPixelsAndBack() {
        // A box placed in the region, then expressed as a normalized box and put
        // back, lands where it started.
        let region = CGRect(x: 100, y: 200, width: 400, height: 300)
        let box = CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.5)
        let view = CaptureGeometry.viewRect(forNormalizedBox: box, in: region)
        let renormalized = CGRect(x: (view.minX - region.minX) / region.width,
                                  y: (view.minY - region.minY) / region.height,
                                  width: view.width / region.width,
                                  height: view.height / region.height)
        XCTAssertEqual(renormalized.minX, box.minX, accuracy: 1e-9)
        XCTAssertEqual(renormalized.minY, box.minY, accuracy: 1e-9)
        XCTAssertEqual(renormalized.width, box.width, accuracy: 1e-9)
        XCTAssertEqual(renormalized.height, box.height, accuracy: 1e-9)
    }
}
