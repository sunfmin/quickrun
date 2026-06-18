import AppKit
import QuickRunKit

/// The Editor: a floating window presenting a Capture. It shows the captured
/// image on a Markup canvas, with a toolbar above and the Recognized-word list
/// beside it. Clicking a word looks it up; the toolbar marks the image up and
/// copies the flattened result. Distinct from the Panel, which only renders
/// Sources.
///
/// Unlike the hotkey-summoned Panel HUD, the Editor does not dismiss on losing
/// key focus — it is a working surface that coexists with the Panel until the
/// user closes it (Esc or the close button).
final class EditorWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let image: NSImage
    private let saveLocation: SaveLocationStore
    private let canvas = MarkupCanvasView()
    private let wordsStack = NSStackView()
    private let statusLabel = NSTextField(labelWithString: "Recognizing…")
    private let colorSwatch = SwatchButton(color: .sealRed, diameter: 24, target: nil, action: nil)
    private let colorPopover = NSPopover()
    private var toolButtons: [MarkupTool: ToolButton] = [:]
    private var keyMonitor: Any?

    private let viewModel = EditorViewModel()

    var onClosed: (() -> Void)?
    var onLookUp: ((String) -> Void)?

    private static let sidebarWidth: CGFloat = 220
    private static let toolbarHeight: CGFloat = 46

    init(image: NSImage, saveLocation: SaveLocationStore) {
        self.image = image
        self.saveLocation = saveLocation
        let windowSize = Self.windowSize(for: image)
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.title = "QuickRun"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.delegate = self
        window.tabbingMode = .disallowed
        window.minSize = NSSize(width: 720, height: 420)

        canvas.image = image
        canvas.onCommit = { [weak self] kind in self?.commit(kind) }
        canvas.onSelect = { [weak self] id in self?.viewModel.select(objectID: id); self?.refresh() }
        canvas.onMove = { [weak self] id, offset in self?.moveSelection(id: id, by: offset) }

        layOutContent()
        refresh()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKey(event) == true ? nil : event
        }
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    func show() {
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Populate the Recognized-word list once OCR finishes.
    func setRecognizedWords(_ words: [String]) {
        viewModel.setRecognizedWords(words)
        wordsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, word) in words.enumerated() {
            let row = WordRowButton(word: word, target: self, action: #selector(wordTapped(_:)))
            row.tag = index
            wordsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: wordsStack.widthAnchor).isActive = true
        }
        statusLabel.stringValue = words.isEmpty ? "No text found" : ""
        statusLabel.isHidden = !words.isEmpty
    }

    // MARK: - Actions

    @objc private func wordTapped(_ sender: NSButton) {
        guard let intent = viewModel.selectWord(at: sender.tag) else { return }
        execute(intent)
    }

    @objc private func toolTapped(_ sender: NSButton) {
        guard let tool = toolButtons.first(where: { $0.value === sender })?.key else { return }
        viewModel.selectTool(tool)
        refresh()
    }

    @objc private func undoTapped() { viewModel.undo(); refresh() }
    @objc private func redoTapped() { viewModel.redo(); refresh() }
    @objc private func deleteTapped() { viewModel.deleteSelection(); refresh() }
    @objc private func copyTapped() { execute(viewModel.copy()) }
    @objc private func saveTapped() { execute(viewModel.save()) }

    @objc private func showColorPopover() {
        let current = viewModel.defaultStyle
        let palette = ColorPaletteViewController(current: current.stroke) { [weak self] color in
            guard let self else { return }
            self.viewModel.setStyle(MarkupStyle(stroke: color, lineWidth: current.lineWidth, fontSize: current.fontSize))
            self.refresh()
        }
        colorPopover.contentViewController = palette
        colorPopover.behavior = .transient
        colorPopover.show(relativeTo: colorSwatch.bounds, of: colorSwatch, preferredEdge: .maxY)
    }

    private func commit(_ kind: MarkupObject.Kind) {
        viewModel.addObject(MarkupObject(kind: kind, style: viewModel.defaultStyle))
        refresh()
    }

    private func moveSelection(id: UUID, by offset: CGSize) {
        viewModel.select(objectID: id)
        viewModel.moveSelection(by: offset)
        refresh()
    }

    private func execute(_ intent: EditorIntent) {
        switch intent {
        case .lookUp(let query):
            onLookUp?(query)
        case .copyToClipboard:
            copyFlattenedToClipboard()
        case .saveToFile:
            saveFlattenedToFile()
        }
    }

    private func copyFlattenedToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let png = MarkupRenderer.pngData(image: image, objects: viewModel.document.objects) {
            pasteboard.setData(png, forType: .png)
        } else {
            pasteboard.writeObjects([MarkupRenderer.flatten(image: image, objects: viewModel.document.objects)])
        }
    }

    private func saveFlattenedToFile() {
        guard let png = MarkupRenderer.pngData(image: image, objects: viewModel.document.objects) else {
            NSSound.beep()
            return
        }
        let folder = saveLocation.folder()
        let url = folder.appendingPathComponent(captureFilename(date: Date()))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: url)
        } catch {
            NSSound.beep()
        }
    }

    /// Returns true if the key was handled.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard window.isKeyWindow else { return false }
        let command = event.modifierFlags.contains(.command)
        let shift = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 53: // Esc
            window.performClose(nil)
            return true
        case 6 where command: // Z
            shift ? redoTapped() : undoTapped()
            return true
        case 51, 117: // delete / forward delete
            guard viewModel.selectedObjectID != nil else { return false }
            deleteTapped()
            return true
        default:
            return false
        }
    }

    private func refresh() {
        canvas.objects = viewModel.document.objects
        canvas.selectedID = viewModel.selectedObjectID
        canvas.tool = viewModel.currentTool
        canvas.activeStyle = viewModel.defaultStyle
        for (tool, button) in toolButtons {
            button.isActive = tool == viewModel.currentTool
        }
        colorSwatch.color = viewModel.defaultStyle.stroke
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        onClosed?()
    }

    // MARK: - Layout

    private func layOutContent() {
        let content = window.contentView!
        let toolbar = makeToolbar()
        let sidebar = makeSidebar()
        canvas.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(toolbar)
        content.addSubview(canvas)
        content.addSubview(sidebar)

        NSLayoutConstraint.activate([
            sidebar.topAnchor.constraint(equalTo: content.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            sidebar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: Self.sidebarWidth),

            toolbar.topAnchor.constraint(equalTo: content.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: Self.toolbarHeight),

            canvas.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            canvas.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            canvas.trailingAnchor.constraint(equalTo: sidebar.leadingAnchor),
        ])
    }

    private func makeToolbar() -> NSView {
        let bar = NSVisualEffectView()
        bar.material = .titlebar
        bar.blendingMode = .behindWindow
        bar.state = .active
        bar.translatesAutoresizingMaskIntoConstraints = false

        let tools: [(MarkupTool, String, String)] = [
            (.select, "cursorarrow", "Select"),
            (.rectangle, "rectangle", "Rectangle"),
            (.arrow, "arrow.up.right", "Arrow"),
            (.text, "textformat", "Text"),
            (.freehand, "pencil.tip", "Pen"),
            (.highlight, "highlighter", "Highlighter"),
            (.blur, "square.grid.3x3.fill", "Blur / redact"),
        ]
        toolButtons = [:]
        let toolViews: [NSView] = tools.map { tool, symbol, tooltip in
            let button = ToolButton(symbol: symbol, tooltip: tooltip)
            button.target = self
            button.action = #selector(toolTapped(_:))
            toolButtons[tool] = button
            return button
        }

        let undo = makeButton(symbol: "arrow.uturn.backward", tooltip: "Undo", action: #selector(undoTapped))
        let redo = makeButton(symbol: "arrow.uturn.forward", tooltip: "Redo", action: #selector(redoTapped))
        let delete = makeButton(symbol: "trash", tooltip: "Delete", action: #selector(deleteTapped))

        colorSwatch.target = self
        colorSwatch.action = #selector(showColorPopover)
        colorSwatch.toolTip = "Stroke colour"

        let leading = NSStackView(views: toolViews + [divider(), undo, redo, delete, divider(), colorSwatch])
        leading.orientation = .horizontal
        leading.spacing = 8
        leading.translatesAutoresizingMaskIntoConstraints = false

        let copy = makeButton(symbol: "doc.on.doc", tooltip: "Copy to clipboard", action: #selector(copyTapped))
        let save = makeButton(symbol: "square.and.arrow.down", tooltip: "Save to folder", action: #selector(saveTapped))
        let trailing = NSStackView(views: [copy, save])
        trailing.orientation = .horizontal
        trailing.spacing = 8
        trailing.translatesAutoresizingMaskIntoConstraints = false

        bar.addSubview(leading)
        bar.addSubview(trailing)
        NSLayoutConstraint.activate([
            leading.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 14),
            leading.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            trailing.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -14),
            trailing.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        return bar
    }

    private func makeButton(symbol: String, tooltip: String, action: Selector?) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = tooltip
        button.target = self
        button.action = action
        return button
    }

    private func divider() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        line.widthAnchor.constraint(equalToConstant: 1).isActive = true
        line.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return line
    }

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

    private static func windowSize(for image: NSImage) -> NSSize {
        let pixels = image.representations.reduce(NSSize.zero) { acc, rep in
            NSSize(width: max(acc.width, CGFloat(rep.pixelsWide)),
                   height: max(acc.height, CGFloat(rep.pixelsHigh)))
        }
        let raw = pixels == .zero ? image.size : pixels
        let pointScale = NSScreen.main?.backingScaleFactor ?? 2
        let imageSize = NSSize(width: raw.width / pointScale, height: raw.height / pointScale)

        var size = NSSize(width: imageSize.width + sidebarWidth,
                          height: imageSize.height + toolbarHeight)
        if let visible = NSScreen.main?.visibleFrame.size {
            let factor = min(1, min(visible.width * 0.9 / size.width,
                                    visible.height * 0.9 / size.height))
            size = NSSize(width: (size.width * factor).rounded(),
                          height: (size.height * factor).rounded())
        }
        return size
    }
}
