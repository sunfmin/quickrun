import AppKit
import XCTest
@testable import QuickRun

/// Renders the *real* Panel masthead (driven by `PanelController.configureForSnapshot`,
/// not a hand-posed copy) over a mocked dictionary result, and checks both that the
/// offscreen snapshot produces light + dark PNGs and that the example look-up flowed
/// through the real `PanelViewModel` into the chrome.
///
/// Set `QUICKRUN_SNAPSHOT_DIR` to dump the PNGs there for visual review.
final class PanelSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
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
            XCTAssertGreaterThan(image?.size.width ?? 0, 600, "\(name).png is too narrow to be the panel")
            XCTAssertGreaterThan(image?.size.height ?? 0, 400, "\(name).png is too short to be the panel")
        }

        if keep == nil { try? FileManager.default.removeItem(at: dir) }
    }

    /// The example look-up reaches the masthead through the real controller — the
    /// view model projected the Query onto the field and configured one tab per Source.
    func testRealControllerProjectsTheLookUp() {
        let (_, controller) = PanelSnapshot.pose(appearance: NSAppearance(named: .aqua)!)
        XCTAssertEqual(controller.queryField.stringValue, "ephemeral")
        XCTAssertEqual(controller.tabBar.count, PanelSnapshot.exampleSources.count)
        XCTAssertEqual(controller.tabBar.selectedIndex, 0)
    }
}
