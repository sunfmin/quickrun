import AppKit
import XCTest
@testable import QuickRunUI

/// Renders the *real* Panel chrome (the masthead built by `PanelChrome`, no
/// hand-mirrored copy) over a mocked dictionary result, and checks the offscreen
/// snapshot actually produces light + dark PNGs of the look-up results window.
///
/// Set `QUICKRUN_SNAPSHOT_DIR` to dump the PNGs there for visual review (a design
/// pass); unset, it renders to a temp dir and cleans up.
final class PanelSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // AppKit view rendering needs an initialised application object even offscreen.
        _ = NSApplication.shared
    }

    func testSnapshotRendersLightAndDarkPNGs() throws {
        let keep = ProcessInfo.processInfo.environment["QUICKRUN_SNAPSHOT_DIR"]
        let dir: URL
        if let keep {
            dir = URL(fileURLWithPath: keep, isDirectory: true).appendingPathComponent("panel", isDirectory: true)
        } else {
            dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("quickrun-panel-snapshot-test", isDirectory: true)
            try? FileManager.default.removeItem(at: dir)
        }

        PanelSnapshot.render(toDirectory: dir.path)

        for name in ["panel-look-up-light", "panel-look-up-dark"] {
            let url = dir.appendingPathComponent("\(name).png")
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "missing \(name).png")
            let image = NSImage(contentsOf: url)
            XCTAssertNotNil(image, "\(name).png did not decode")
            // The full panel window, rendered @2x — wide and tall.
            XCTAssertGreaterThan(image?.size.width ?? 0, 600, "\(name).png is too narrow to be the panel")
            XCTAssertGreaterThan(image?.size.height ?? 0, 400, "\(name).png is too short to be the panel")
        }

        if keep == nil { try? FileManager.default.removeItem(at: dir) }
    }
}
