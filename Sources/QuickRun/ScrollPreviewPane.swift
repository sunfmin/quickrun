import AppKit
import QuickRunKit
import QuickRunUI

/// The live Scroll Preview (ADR 0004): a borderless pane beside the Main Box that
/// shows the *whole* Scroll Capture as it accumulates — no scrollbar. It grows to
/// fill the available screen height (`ScrollPreviewLayout`), then scales the whole
/// image down and narrows so the entire stitch stays visible.
///
/// Its actions live in a separate **floating pill toolbar** below the preview,
/// styled like the Editor's toolbar (rounded `.menu` material, icon buttons) but
/// with only the few tools a Scroll Capture needs: Copy and Save (which finalize —
/// they double as "done") and Cancel. The grow-then-narrow sizing is the pure
/// `ScrollPreviewLayout` in QuickRunKit; this type is the AppKit glue.
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
    /// Called when the user taps Cancel — keeps nothing (like Esc).
    var onCancel: (() -> Void)?

    /// The image pane and the floating pill of actions beneath it.
    private let panel: NSPanel
    private let imageView: NSImageView
    private var controls: NSPanel!
    private var controlsRow: NSStackView?
    private var controlsSize: NSSize = .zero

    /// The current stitched image — copied/saved as-is when the user finalizes.
    private var image: NSImage?

    private static let margin: CGFloat = 8
    private static let gap: CGFloat = 12

    init(mainBox: CGRect, screen: NSScreen, scale: CGFloat, saveLocation: SaveLocationStore) {
        self.mainBox = mainBox
        self.screen = screen
        self.scale = scale
        self.saveLocation = saveLocation

        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true

        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        container.layer?.cornerRadius = 8
        container.layer?.masksToBounds = true

        imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignTop
        imageView.autoresizingMask = [.width, .height]
        container.addSubview(imageView)
        panel.contentView = container

        super.init()
        buildControls()
    }

    func show() {
        panel.orderFrontRegardless()
        controls.orderFrontRegardless()
    }

    func close() {
        panel.orderOut(nil)
        controls.orderOut(nil)
    }

    /// Replace the previewed image with the latest stitch and re-lay-out — resize
    /// to the `ScrollPreviewLayout` size, reposition beside the Main Box, and float
    /// the controls below.
    func update(image: NSImage) {
        self.image = image
        imageView.image = image

        let pixelSize = pixelSize(of: image)
        let layout = ScrollPreviewLayout.layout(
            stitchedPixelSize: pixelSize, scale: scale, availableHeight: availableHeight())
        let size = layout.displaySize
        guard size.width > 0, size.height > 0 else { return }

        panel.setContentSize(size)
        imageView.frame = NSRect(origin: .zero, size: size)
        panel.setFrameOrigin(imageOrigin(forSize: size))
        positionControls(below: panel.frame)
    }

    // MARK: - Layout maths

    /// Screen height available to the image — the floating controls and the gaps
    /// around them are reserved so they never fall off-screen.
    private func availableHeight() -> CGFloat {
        screen.visibleFrame.height - controlsSize.height - Self.gap - 2 * Self.margin
    }

    /// Place the image pane to the right of the Main Box, or to the left when
    /// there's no room; grow downward from the box top, clamped within the visible
    /// frame and leaving room for the controls beneath.
    private func imageOrigin(forSize size: NSSize) -> NSPoint {
        let visible = screen.visibleFrame
        var x = mainBox.maxX + Self.gap
        if x + size.width > visible.maxX - Self.margin {
            x = mainBox.minX - Self.gap - size.width
        }
        x = min(max(x, visible.minX + Self.margin), visible.maxX - size.width - Self.margin)

        let top = min(mainBox.maxY, visible.maxY - Self.margin)
        var y = top - size.height
        let reserveBottom = visible.minY + Self.margin + controlsSize.height + Self.gap
        if y < reserveBottom { y = reserveBottom }
        return NSPoint(x: x, y: y)
    }

    /// Centre the controls pill under the image pane (above it if there's no room),
    /// clamped to the visible frame.
    private func positionControls(below imageFrame: NSRect) {
        let visible = screen.visibleFrame
        var x = imageFrame.midX - controlsSize.width / 2
        x = min(max(x, visible.minX + Self.margin), visible.maxX - controlsSize.width - Self.margin)

        var y = imageFrame.minY - Self.gap - controlsSize.height
        if y < visible.minY + Self.margin { y = imageFrame.maxY + Self.gap }
        y = min(y, visible.maxY - controlsSize.height - Self.margin)
        controls.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func pixelSize(of image: NSImage) -> CGSize {
        if let rep = image.representations.first {
            return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return CGSize(width: image.size.width * scale, height: image.size.height * scale)
    }

    // MARK: - Controls (floating pill, styled like the Editor toolbar)

    private func buildControls() {
        let row = makeControlsRow()
        controlsRow = row

        let bar = NSVisualEffectView()
        bar.material = .menu
        bar.blendingMode = .behindWindow
        bar.state = .active
        bar.wantsLayer = true
        bar.layer?.cornerRadius = ToolbarStyle.cornerRadius
        bar.layer?.masksToBounds = true
        bar.layer?.borderWidth = 0.5
        bar.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.4).cgColor
        bar.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            row.topAnchor.constraint(equalTo: bar.topAnchor),
            row.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
        ])

        let size = row.fittingSize
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = bar
        panel.setContentSize(size)
        controls = panel
        controlsSize = panel.frame.size
    }

    /// The pill's action row — Copy and Save (which double as "done"), a divider, and
    /// a brick-red Cancel. Built here so the live pill and `SnapshotTests` lay out the
    /// identical row instead of a hand-mirrored copy.
    private func makeControlsRow() -> NSStackView {
        // Monochrome line icons like the Editor's actions; only Cancel carries a
        // restrained red, so the pill reads calm.
        let copy = iconButton("doc.on.clipboard", "Copy to clipboard", #selector(copyTapped), tint: .secondaryLabelColor)
        let save = iconButton("square.and.arrow.down", "Save to folder", #selector(saveTapped), tint: .secondaryLabelColor)
        let cancel = iconButton("xmark", "Cancel", #selector(cancelTapped), tint: ToolbarStyle.destructive)

        let separator = divider()
        let row = NSStackView(views: [copy, save, separator, cancel])
        row.orientation = .horizontal
        row.spacing = ToolbarStyle.rowSpacing
        row.setCustomSpacing(14, after: save)
        row.setCustomSpacing(14, after: separator)
        row.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    /// The action row, for offscreen rendering on a flat card (the pill's
    /// `NSVisualEffectView` blur can't render offscreen).
    var snapshotControlsRow: NSView? { controlsRow }

    private func iconButton(_ symbol: String, _ tooltip: String, _ action: Selector, tint: NSColor) -> NSButton {
        let button = NSButton()
        button.image = ToolbarStyle.icon(symbol, tooltip)
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.contentTintColor = tint
        button.toolTip = tooltip
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: ToolbarStyle.buttonSize).isActive = true
        button.heightAnchor.constraint(equalToConstant: ToolbarStyle.buttonSize).isActive = true
        return button
    }

    private func divider() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        line.widthAnchor.constraint(equalToConstant: 1).isActive = true
        line.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return line
    }

    // MARK: - Actions

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

    @objc private func cancelTapped() {
        onCancel?()
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
