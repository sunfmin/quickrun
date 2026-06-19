import AppKit
import QuickRunKit

/// Shows a stitched scroll Capture (ADR 0004) in a scrollable window — the
/// non-in-place surface, since the tall image exceeds the screen. Copy and Save
/// mirror the overlay's terminal actions. Markup and OCR over the stitched image
/// are a later phase; this phase reviews, copies, and saves it.
final class ScrollPreviewController: NSWindowController {
    private let image: NSImage
    private let saveLocation: SaveLocationStore
    var onClosed: (() -> Void)?

    init(image: NSImage, saveLocation: SaveLocationStore) {
        self.image = image
        self.saveLocation = saveLocation

        let visibleHeight = min(image.size.height, (NSScreen.main?.visibleFrame.height ?? 800) - 120)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: image.size.width, height: visibleHeight + 44),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "Scroll Capture"
        super.init(window: window)

        let bar = makeBar()
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let imageView = NSImageView()
        imageView.image = image
        imageView.imageScaling = .scaleNone
        imageView.imageAlignment = .alignTop
        imageView.frame = NSRect(origin: .zero, size: image.size)
        imageView.setFrameSize(image.size)
        scroll.documentView = imageView

        let content = NSView()
        content.addSubview(bar)
        content.addSubview(scroll)
        bar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: content.topAnchor),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 44),
            scroll.topAnchor.constraint(equalTo: bar.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.contentView = content
        window.center()
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeBar() -> NSView {
        let bar = NSVisualEffectView()
        bar.material = .titlebar
        bar.blendingMode = .behindWindow

        let copy = NSButton(title: "Copy", target: self, action: #selector(copyTapped))
        let save = NSButton(title: "Save", target: self, action: #selector(saveTapped))
        let row = NSStackView(views: [copy, save])
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(row)
        NSLayoutConstraint.activate([
            row.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
            row.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        return bar
    }

    @objc private func copyTapped() {
        guard let png = pngData() else { NSSound.beep(); return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
    }

    @objc private func saveTapped() {
        guard let png = pngData() else { NSSound.beep(); return }
        let folder = saveLocation.folder()
        let url = folder.appendingPathComponent(captureFilename(date: Date()))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            NSSound.beep()
        }
    }

    /// PNG of the stitched image at its native-resolution backing.
    private func pngData() -> Data? {
        if let rep = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first {
            return rep.representation(using: .png, properties: [:])
        }
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

extension ScrollPreviewController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        onClosed?()
    }
}
