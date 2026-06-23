import AppKit
import XCTest
import QuickRunKit
@testable import QuickRun

/// Renders the *real* floating toolbars (built by `CaptureOverlayController` and
/// `ScrollPreviewPane`, not hand-mirrored copies) and checks both that the offscreen
/// snapshot produces light + dark PNGs and that the posed editor state was synced
/// onto the toolbar through the real view model.
///
/// Set `QUICKRUN_SNAPSHOT_DIR` to dump the PNGs there for visual review.
final class ToolbarSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    func testSnapshotRendersLightAndDarkPNGs() throws {
        let keep = ProcessInfo.processInfo.environment["QUICKRUN_SNAPSHOT_DIR"]
        let dir: URL
        if let keep {
            dir = URL(fileURLWithPath: keep, isDirectory: true).appendingPathComponent("toolbar", isDirectory: true)
        } else {
            dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("quickrun-toolbar-snapshot-test", isDirectory: true)
            try? FileManager.default.removeItem(at: dir)
        }

        ToolbarSnapshot.render(toDirectory: dir.path)

        for name in ["toolbar-editor-light", "toolbar-editor-dark",
                     "toolbar-scroll-light", "toolbar-scroll-dark"] {
            let url = dir.appendingPathComponent("\(name).png")
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "missing \(name).png")
            let image = NSImage(contentsOf: url)
            XCTAssertNotNil(image, "\(name).png did not decode")
            XCTAssertGreaterThan(image?.size.width ?? 0, 200, "\(name).png is too narrow to be the bar")
            XCTAssertGreaterThan(image?.size.height ?? 0, 20, "\(name).png is too short to be the bar")
        }

        if keep == nil { try? FileManager.default.removeItem(at: dir) }
    }

    /// The posed view model was synced onto the real toolbar: the held tool wears its
    /// chip, and the swatch + width dot matching the style are ringed.
    func testEditorToolbarSyncsPosedState() {
        let content = ToolbarSnapshot.editorToolbar()

        XCTAssertEqual(content.toolButtons[ToolbarSnapshot.posedTool]?.isActive, true)
        XCTAssertEqual(content.toolButtons[.select]?.isActive, false)

        let style = ToolbarSnapshot.posedStyle
        let selectedSwatches = content.swatchButtons.filter(\.isSelectedSwatch)
        XCTAssertEqual(selectedSwatches.count, 1)
        XCTAssertEqual(selectedSwatches.first?.color, style.stroke)

        let selectedWidths = content.widthButtons.filter(\.isSelectedWidth)
        XCTAssertEqual(selectedWidths.count, 1)
        XCTAssertEqual(selectedWidths.first?.width, style.lineWidth)
    }

    /// The scroll pill is the real `ScrollPreviewPane` row — Copy, Save, a divider,
    /// and Cancel — not a reconstruction.
    func testScrollPillIsTheRealRow() {
        let row = ToolbarSnapshot.scrollPill()
        XCTAssertEqual(row.subviews.count, 4, "copy · save · divider · cancel")
    }
}
