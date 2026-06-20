import AppKit
import XCTest
import QuickRunKit
@testable import QuickRunUI

/// Renders the *real* editor toolbar component (no hand-mirrored copy) under test,
/// both structurally (the segment groups are wired correctly) and visually (the
/// offscreen snapshot actually produces light + dark PNGs).
final class EditorToolbarTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // AppKit view rendering needs an initialised application object even offscreen.
        _ = NSApplication.shared
    }

    func testBuildWiresEveryGroup() {
        let content = EditorToolbarContent.build()

        // Nine annotation tools, in the documented order, each with a button.
        XCTAssertEqual(content.toolButtons.count, 9)
        for tool in [MarkupTool.select, .rectangle, .ellipse, .emoji, .arrow, .freehand, .highlight, .blur, .text] {
            XCTAssertNotNil(content.toolButtons[tool], "missing tool button for \(tool)")
        }

        // Every non-tool action — scroll-capture, history, finish, discard — has a button.
        XCTAssertEqual(content.actionButtons.count, EditorToolbarContent.Action.allCases.count)
        for action in EditorToolbarContent.Action.allCases {
            XCTAssertNotNil(content.actionButtons[action], "missing action button for \(action)")
        }

        // The style strip mirrors the single source of truth.
        XCTAssertEqual(content.swatchButtons.count, StylePresets.colors.count)
        XCTAssertEqual(content.widthButtons.count, StylePresets.widths.count)
    }

    func testCancelButtonWearsTheDestructiveTint() {
        let content = EditorToolbarContent.build()
        XCTAssertEqual(content.actionButtons[.cancel]?.contentTintColor, ToolbarStyle.destructive)
    }

    func testPosingAToolShowsItsActiveChip() {
        let content = EditorToolbarContent.build()
        content.toolButtons[.freehand]?.isActive = true
        XCTAssertEqual(content.toolButtons[.freehand]?.isActive, true)
        XCTAssertEqual(content.toolButtons[.select]?.isActive, false)
    }

    func testSnapshotRendersLightAndDarkPNGs() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("quickrun-toolbar-snapshot-test", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)

        ToolbarSnapshot.render(toDirectory: dir.path)

        for name in ["toolbar-editor-light", "toolbar-editor-dark",
                     "toolbar-scroll-light", "toolbar-scroll-dark"] {
            let url = dir.appendingPathComponent("\(name).png")
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "missing \(name).png")
            let image = NSImage(contentsOf: url)
            XCTAssertNotNil(image, "\(name).png did not decode")
            // A non-empty bar, rendered @2x — wide and short.
            XCTAssertGreaterThan(image?.size.width ?? 0, 200, "\(name).png is too narrow to be the bar")
            XCTAssertGreaterThan(image?.size.height ?? 0, 20, "\(name).png is too short to be the bar")
        }

        try? FileManager.default.removeItem(at: dir)
    }
}
