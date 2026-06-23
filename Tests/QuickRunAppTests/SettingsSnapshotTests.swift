import AppKit
import XCTest
@testable import QuickRun

/// Renders the *real* `SettingsWindowController` over ephemeral, example-seeded
/// stores, and checks both that the offscreen snapshot produces light + dark PNGs
/// and that the seeded data flowed through the real controller — its own table data
/// source, hotkey formatter, and save-location formatting — into the rendered
/// controls. No part of the window is re-implemented in the test.
///
/// Set `QUICKRUN_SNAPSHOT_DIR` to dump the PNGs there for visual review (a design
/// pass); unset, it renders to a temp dir and cleans up.
final class SettingsSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // AppKit view rendering needs an initialised application object even offscreen.
        _ = NSApplication.shared
    }

    func testSnapshotRendersLightAndDarkPNGs() throws {
        let keep = ProcessInfo.processInfo.environment["QUICKRUN_SNAPSHOT_DIR"]
        let dir: URL
        if let keep {
            dir = URL(fileURLWithPath: keep, isDirectory: true).appendingPathComponent("settings", isDirectory: true)
        } else {
            dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("quickrun-settings-snapshot-test", isDirectory: true)
            try? FileManager.default.removeItem(at: dir)
        }

        SettingsSnapshot.render(toDirectory: dir.path)

        for name in ["settings-light", "settings-dark"] {
            let url = dir.appendingPathComponent("\(name).png")
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "missing \(name).png")
            let image = NSImage(contentsOf: url)
            XCTAssertNotNil(image, "\(name).png did not decode")
            // The full settings content, rendered @2x — wide and tall.
            XCTAssertGreaterThan(image?.size.width ?? 0, 500, "\(name).png is too narrow to be the settings window")
            XCTAssertGreaterThan(image?.size.height ?? 0, 400, "\(name).png is too short to be the settings window")
        }

        if keep == nil { try? FileManager.default.removeItem(at: dir) }
    }

    /// The seeded stores reach the real controls through the real controller — proving
    /// the snapshot drives the live code path, not a hand-built mirror.
    func testRealControllerRendersSeededData() {
        let (_, controller) = SettingsSnapshot.pose(appearance: NSAppearance(named: .aqua)!)
        let table = controller.tableView

        // The Sources list is populated by the controller's own data source.
        XCTAssertEqual(table.numberOfRows, SettingsSnapshot.exampleSources.count)

        // The name cell (column 0) and URL cell (column 1) render through the real
        // `viewFor`, with the URL set in a monospaced face — a template is an editable
        // pattern, not prose.
        let nameCell = table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTextField
        XCTAssertEqual(nameCell?.stringValue, SettingsSnapshot.exampleSources[0].name)
        let urlCell = table.view(atColumn: 1, row: 0, makeIfNecessary: true) as? NSTextField
        XCTAssertEqual(urlCell?.stringValue, SettingsSnapshot.exampleSources[0].urlTemplate)
        XCTAssertEqual(urlCell?.font?.isFixedPitch, true, "URL templates should be monospaced")

        // The hotkey title is formatted by the real HotkeyFormatter from the seeded ⌥D.
        XCTAssertEqual(controller.hotkeyButton.title, "⌥D")

        // The injected granted state hides the grant button.
        XCTAssertEqual(controller.permissionLabel.stringValue, "Granted ✓")
        XCTAssertTrue(controller.grantButton.isHidden)

        // The save location is abbreviated by the controller from the seeded folder.
        XCTAssertEqual(controller.saveLocationLabel.stringValue, "~/Desktop")
    }
}
