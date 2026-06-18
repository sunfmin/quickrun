import AppKit

/// The Editor: a floating window presenting a Capture. For now it just shows the
/// captured image; later slices add the Recognized-word list, the Markup
/// toolbar, and saving. Distinct from the Panel, which only renders Sources.
///
/// Unlike the hotkey-summoned Panel HUD, the Editor does not dismiss on losing
/// key focus — it is a working surface that coexists with the Panel until the
/// user closes it (Esc or the close button).
final class EditorWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let imageView = NSImageView()
    private var escMonitor: Any?

    /// Called when the window closes, so the owner can drop its reference.
    var onClosed: (() -> Void)?

    init(image: NSImage) {
        let size = Self.initialSize(for: image)
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.title = "QuickRun"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = self
        window.tabbingMode = .disallowed

        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.frame = NSRect(origin: .zero, size: size)
        imageView.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(imageView)

        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window.isVisible, event.keyCode == 53 else { return event }
            self.window.performClose(nil)
            return nil
        }
    }

    deinit {
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
    }

    func show() {
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        onClosed?()
    }

    // MARK: - Sizing

    /// The image at its visual (point) size — pixel dimensions divided by the
    /// main display's scale — capped to 90% of the visible screen, aspect kept.
    private static func initialSize(for image: NSImage) -> NSSize {
        let pixels = image.representations.reduce(NSSize.zero) { acc, rep in
            NSSize(width: max(acc.width, CGFloat(rep.pixelsWide)),
                   height: max(acc.height, CGFloat(rep.pixelsHigh)))
        }
        let raw = pixels == .zero ? image.size : pixels
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        var size = NSSize(width: raw.width / scale, height: raw.height / scale)

        if let visible = NSScreen.main?.visibleFrame.size {
            let factor = min(1, min(visible.width * 0.9 / size.width,
                                    visible.height * 0.9 / size.height))
            size = NSSize(width: (size.width * factor).rounded(),
                          height: (size.height * factor).rounded())
        }
        return size
    }
}
