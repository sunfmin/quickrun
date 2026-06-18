import AppKit
import QuickRunKit

/// The Editor: a floating window presenting a Capture. It shows the captured
/// image alongside the list of Recognized words; clicking a word looks it up.
/// Later slices add the Markup toolbar and saving. Distinct from the Panel,
/// which only renders Sources.
///
/// Unlike the hotkey-summoned Panel HUD, the Editor does not dismiss on losing
/// key focus — it is a working surface that coexists with the Panel until the
/// user closes it (Esc or the close button).
final class EditorWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let imageView = NSImageView()
    private let wordsStack = NSStackView()
    private let statusLabel = NSTextField(labelWithString: "Recognizing…")
    private var escMonitor: Any?

    private var viewModel = EditorViewModel()

    /// Called when the window closes, so the owner can drop its reference.
    var onClosed: (() -> Void)?
    /// Called with the Query when the user picks a Recognized word.
    var onLookUp: ((String) -> Void)?

    private static let sidebarWidth: CGFloat = 220

    init(image: NSImage) {
        let imageSize = Self.imagePointSize(for: image)
        let windowSize = Self.windowSize(forImage: imageSize)
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
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

        let content = window.contentView!
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let sidebar = makeSidebar()
        content.addSubview(imageView)
        content.addSubview(sidebar)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            imageView.topAnchor.constraint(equalTo: content.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            imageView.trailingAnchor.constraint(equalTo: sidebar.leadingAnchor),

            sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: Self.sidebarWidth),
        ])

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

    /// Populate the Recognized-word list once OCR finishes.
    func setRecognizedWords(_ words: [String]) {
        viewModel = EditorViewModel(recognizedWords: words)
        wordsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, word) in words.enumerated() {
            let button = NSButton(title: word, target: self, action: #selector(wordTapped(_:)))
            button.isBordered = false
            button.setButtonType(.momentaryChange)
            button.alignment = .left
            button.contentTintColor = .labelColor
            button.font = .quickRunSerif(ofSize: 15, weight: .regular)
            button.tag = index
            wordsStack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: wordsStack.widthAnchor).isActive = true
        }
        statusLabel.stringValue = words.isEmpty ? "No text found" : ""
        statusLabel.isHidden = !words.isEmpty
    }

    @objc private func wordTapped(_ sender: NSButton) {
        guard let query = viewModel.query(forWordAt: sender.tag) else { return }
        onLookUp?(query)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        onClosed?()
    }

    // MARK: - Sidebar

    private func makeSidebar() -> NSView {
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .active
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        let header = NSTextField(labelWithString: "Words")
        header.font = .quickRunSerif(ofSize: 13, weight: .semibold)
        header.textColor = .secondaryLabelColor
        header.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .tertiaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        wordsStack.orientation = .vertical
        wordsStack.alignment = .leading
        wordsStack.spacing = 2
        wordsStack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = wordsStack

        sidebar.addSubview(header)
        sidebar.addSubview(statusLabel)
        sidebar.addSubview(scroll)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 14),
            header.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -16),

            statusLabel.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            statusLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor),

            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -10),
            scroll.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -12),

            wordsStack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            wordsStack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            wordsStack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])
        return sidebar
    }

    // MARK: - Sizing

    /// The image at its visual (point) size — pixel dimensions divided by the
    /// main display's scale.
    private static func imagePointSize(for image: NSImage) -> NSSize {
        let pixels = image.representations.reduce(NSSize.zero) { acc, rep in
            NSSize(width: max(acc.width, CGFloat(rep.pixelsWide)),
                   height: max(acc.height, CGFloat(rep.pixelsHigh)))
        }
        let raw = pixels == .zero ? image.size : pixels
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        return NSSize(width: raw.width / scale, height: raw.height / scale)
    }

    /// The image (at point size) plus the sidebar, capped to 90% of the visible
    /// screen with the image's aspect kept.
    private static func windowSize(forImage image: NSSize) -> NSSize {
        var size = NSSize(width: image.width + sidebarWidth, height: image.height)
        if let visible = NSScreen.main?.visibleFrame.size {
            let factor = min(1, min(visible.width * 0.9 / size.width,
                                    visible.height * 0.9 / size.height))
            size = NSSize(width: (size.width * factor).rounded(),
                          height: (size.height * factor).rounded())
        }
        return size
    }
}
