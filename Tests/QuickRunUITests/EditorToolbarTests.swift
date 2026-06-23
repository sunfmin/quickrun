import AppKit
import XCTest
import QuickRunKit
@testable import QuickRunUI

/// Structural checks on the *real* editor toolbar component (no hand-mirrored copy):
/// the segment groups are wired correctly and the destructive tint is set. The
/// offscreen rendering of this bar lives in `ToolbarSnapshotTests`, which drives the
/// live `CaptureOverlayController`.
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
}
