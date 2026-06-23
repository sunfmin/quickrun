import AppKit
import QuickRunKit
import QuickRunUI
@testable import QuickRun

/// Renders the floating toolbars — the editor toolbar and the Scroll Preview pill —
/// to PNGs offscreen. Driven by `ToolbarSnapshotTests`.
///
/// Both bars are built by their *real* controllers: `CaptureOverlayController`
/// builds and state-syncs the editor toolbar from a posed `EditorViewModel`, and
/// `ScrollPreviewPane` builds its action pill. No bar is hand-mirrored. The one
/// thing that can't render offscreen — the `NSVisualEffectView` blur — is replaced
/// by a flat card; the bars' contents are the live ones.
enum ToolbarSnapshot {
    /// The posed editor state: a held tool and a selected ink + width, all real
    /// `StylePresets` values fed through the view model.
    static let posedTool: MarkupTool = .freehand
    static var posedStyle: MarkupStyle {
        MarkupStyle(stroke: StylePresets.colors[0], lineWidth: StylePresets.widths[1])
    }

    static func render(toDirectory directory: String) {
        let dir = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for (suffix, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let appearance = NSAppearance(named: appearanceName)!
            SnapshotImage.write(toolbarCard(editorToolbar().view, appearance: appearance),
                                to: dir.appendingPathComponent("toolbar-editor-\(suffix).png"))
            SnapshotImage.write(toolbarCard(scrollPill(), appearance: appearance),
                                to: dir.appendingPathComponent("toolbar-scroll-\(suffix).png"))
        }
    }

    /// The real editor toolbar, built and state-synced by `CaptureOverlayController`
    /// from the posed view model. Returns the content so a test can assert the synced
    /// selection (the held tool's chip, the ringed swatch/width).
    static func editorToolbar() -> EditorToolbarContent {
        let overlay = CaptureOverlayController(frozen: dummyFrozen(), saveLocation: ephemeralSaveLocation())
        overlay.configureForSnapshot(tool: posedTool, style: posedStyle)
        return overlay.makeEditorToolbarContent()
    }

    /// The real Scroll Preview action pill, built by `ScrollPreviewPane`.
    static func scrollPill() -> NSView {
        let pane = ScrollPreviewPane(
            mainBox: NSRect(x: 0, y: 0, width: 400, height: 300),
            screen: NSScreen.main!,
            scale: NSScreen.main!.backingScaleFactor,
            saveLocation: ephemeralSaveLocation()
        )
        return pane.snapshotControlsRow!
    }

    // MARK: - Offscreen-safe stand-ins for the live capture dependencies

    private static func ephemeralSaveLocation() -> SaveLocationStore {
        let suite = "QuickRun.snapshot.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return SaveLocationStore(defaults: defaults)
    }

    /// A 2×2 still — the overlay only needs a valid `FrozenDisplay` to build its
    /// toolbar; the snapshot never draws the frozen image.
    private static func dummyFrozen() -> FrozenDisplay {
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = ctx.makeImage()!
        let screen = NSScreen.main!
        return FrozenDisplay(image: image, frame: NSRect(x: 0, y: 0, width: 200, height: 200),
                             scale: screen.backingScaleFactor, screen: screen)
    }
}
