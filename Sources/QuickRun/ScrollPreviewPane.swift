import AppKit
import QuickRunKit

/// The live Scroll Preview (ADR 0004): a borderless pane beside the Main Box that
/// shows the *whole* Scroll Capture as it accumulates — no scrollbar. It grows to
/// fill the available screen height (`ScrollPreviewLayout`), then scales the whole
/// image down and narrows so the entire stitch stays visible. It carries only Copy
/// and Save, which each finalize the Capture (they double as "done").
///
/// All the grow-then-narrow sizing is the pure `ScrollPreviewLayout` in QuickRunKit;
/// this type is the AppKit glue (the panel, the image view, the buttons) that can
/// only be exercised live. It replaces the old standalone scrollable preview window.
final class ScrollPreviewPane: NSObject {
    /// `mainBox` is in global screen points (AppKit, bottom-left origin) — the
    /// fixed region the user scrolls content through.
    private let mainBox: CGRect
    private let screen: NSScreen
    private let scale: CGFloat
    private let saveLocation: SaveLocationStore

    /// Called after Copy or Save acts — Copy/Save double as "done", so the
    /// controller stops the driver and tears the capture session down.
    var onFinish: (() -> Void)?

    private let panel: NSPanel
    private let container: NSView
    private let imageView: NSImageView
    private let bar: NSView

    /// The current stitched image — copied/saved as-is when the user finalizes.
    private var image: NSImage?

    private static let barHeight: CGFloat = 36
    private static let margin: CGFloat = 8
    private static let gap: CGFloat = 12
    private static let minWidth: CGFloat = 150

    init(mainBox: CGRect, screen: NSScreen, scale: CGFloat, saveLocation: SaveLocationStore) {
        self.mainBox = mainBox
        self.screen = screen
        self.scale = scale
        self.saveLocation = saveLocation

        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.minWidth, height: Self.barHeight),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true

        container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        container.layer?.cornerRadius = 8
        container.layer?.masksToBounds = true

        imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignTop
        imageView.wantsLayer = true

        bar = ScrollPreviewPane.makeBar()
        container.addSubview(imageView)
        container.addSubview(bar)
        panel.contentView = container

        super.init()
        wireButtons()
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func close() {
        panel.orderOut(nil)
    }

    /// Replace the previewed image with the latest stitch and re-lay-out the pane —
    /// resize to the `ScrollPreviewLayout` size and reposition beside the Main Box.
    func update(image: NSImage) {
        self.image = image
        imageView.image = image

        let pixelSize = pixelSize(of: image)
        let layout = ScrollPreviewLayout.layout(
            stitchedPixelSize: pixelSize, scale: scale, availableHeight: availableHeight())
        guard layout.displaySize.width > 0, layout.displaySize.height > 0 else { return }

        let imageW = layout.displaySize.width
        let imageH = layout.displaySize.height
        let panelW = max(imageW, Self.minWidth)
        let panelH = imageH + Self.barHeight

        panel.setContentSize(NSSize(width: panelW, height: panelH))
        container.frame = NSRect(x: 0, y: 0, width: panelW, height: panelH)
        // Bottom-left origin: bar along the bottom, image centered above it.
        bar.frame = NSRect(x: 0, y: 0, width: panelW, height: Self.barHeight)
        imageView.frame = NSRect(x: (panelW - imageW) / 2, y: Self.barHeight, width: imageW, height: imageH)

        panel.setFrameOrigin(origin(forPanelSize: NSSize(width: panelW, height: panelH)))
    }

    // MARK: - Layout maths

    /// Screen height available to the *image* (the bar and margins are reserved).
    private func availableHeight() -> CGFloat {
        screen.visibleFrame.height - Self.barHeight - 2 * Self.margin
    }

    /// Place the pane to the right of the Main Box, or to the left when there's no
    /// room; grow downward from the box top, clamped within the visible frame.
    private func origin(forPanelSize size: NSSize) -> NSPoint {
        let visible = screen.visibleFrame
        var x = mainBox.maxX + Self.gap
        if x + size.width > visible.maxX - Self.margin {
            x = mainBox.minX - Self.gap - size.width
        }
        x = min(max(x, visible.minX + Self.margin), visible.maxX - size.width - Self.margin)

        let top = min(mainBox.maxY, visible.maxY - Self.margin)
        var y = top - size.height
        if y < visible.minY + Self.margin { y = visible.minY + Self.margin }
        return NSPoint(x: x, y: y)
    }

    private func pixelSize(of image: NSImage) -> CGSize {
        if let rep = image.representations.first {
            return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return CGSize(width: image.size.width * scale, height: image.size.height * scale)
    }

    // MARK: - Buttons

    private static func makeBar() -> NSView {
        let bar = NSVisualEffectView()
        bar.material = .menu
        bar.blendingMode = .behindWindow
        bar.state = .active
        return bar
    }

    private func wireButtons() {
        let copy = NSButton(title: "Copy", target: self, action: #selector(copyTapped))
        let save = NSButton(title: "Save", target: self, action: #selector(saveTapped))
        let row = NSStackView(views: [copy, save])
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(row)
        NSLayoutConstraint.activate([
            row.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
            row.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
    }

    @objc private func copyTapped() {
        guard let png = pngData() else { NSSound.beep(); return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        onFinish?()
    }

    @objc private func saveTapped() {
        guard let png = pngData() else { NSSound.beep(); return }
        let folder = saveLocation.folder()
        let url = folder.appendingPathComponent(captureFilename(date: Date()))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: url)
            onFinish?()
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            NSSound.beep()
        }
    }

    /// PNG of the stitched image at its native-resolution backing.
    private func pngData() -> Data? {
        guard let image else { return nil }
        if let rep = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first {
            return rep.representation(using: .png, properties: [:])
        }
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
