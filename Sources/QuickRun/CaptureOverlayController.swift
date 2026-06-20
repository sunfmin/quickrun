import AppKit
import QuickRunKit

/// The Editor, redesigned as an in-place overlay (ADR 0003): a borderless,
/// full-display window showing the frozen screen dimmed, on which the user drags
/// out the Capture region right where the content sits, then marks it up with a
/// floating toolbar that tracks the region. Marks live in frozen-screen point
/// space and are flattened cropped to the region when copied or saved.
///
/// The controller owns the pure `EditorViewModel` (tool, selection, Markup
/// document, undo/redo) and the toolbar chrome; the overlay view owns drawing
/// and turning drags into regions and marks. #20 hangs clickable Recognized
/// words off this same overlay; #18 adds region resize handles.
final class CaptureOverlayController: NSObject {
    private let window: OverlayWindow
    private let view: CaptureOverlayView
    private let frozen: FrozenDisplay
    private let saveLocation: SaveLocationStore

    private let viewModel = EditorViewModel()
    private let recognizer: TextRecognizing = VisionTextRecognizer()
    /// Debounces OCR so a flurry of region changes (resizing) re-runs it once.
    private var recognizeWork: DispatchWorkItem?

    /// Forward a clicked Recognized word to the app, which looks it up in the
    /// Panel. Set by the AppDelegate.
    var onLookUpWord: ((String) -> Void)?

    // Scroll-capture run state (ADR 0004): the driver, the click-through Main Box
    // outline, the live Scroll Preview pane, the Esc monitor, and whether the user
    // cancelled. Copy/Save on the pane finalize; Esc cancels.
    private var scrollDriver: ScrollCaptureDriver?
    private var scrollGuide: NSPanel?
    private var scrollPane: ScrollPreviewPane?
    private var scrollStopMonitors: [Any] = []
    private var scrollCancelled = false

    // Floating toolbar, shown once a region is committed.
    private var toolbar: NSPanel?
    private var toolButtons: [MarkupTool: ToolButton] = [:]
    // The persistent ink + width strip beneath the tool row — always visible, no
    // popover. Each button restyles the selection (or sets the default) via the
    // view model; `refresh()` rings whichever matches the current style.
    private var swatchButtons: [SwatchButton] = []
    private var widthButtons: [WidthDotButton] = []
    private static let toolbarHeight: CGFloat = 44
    private static let toolbarGap: CGFloat = 12

    var onClosed: (() -> Void)?

    init(frozen: FrozenDisplay, saveLocation: SaveLocationStore) {
        self.frozen = frozen
        self.saveLocation = saveLocation
        window = OverlayWindow(
            contentRect: frozen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        view = CaptureOverlayView(frozen: frozen)
        super.init()

        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.contentView = view

        view.onRegionCommitted = { [weak self] rect in self?.regionCommitted(rect) }
        view.onCancel = { [weak self] in self?.close() }
        view.onConfirmCopy = { [weak self] in self?.copyAndClose() }
        view.onCommitMark = { [weak self] kind in self?.commitMark(kind) }
        view.onSelectMark = { [weak self] id in self?.viewModel.select(objectID: id); self?.refresh() }
        view.onMoveMark = { [weak self] id, offset in self?.moveMark(id, by: offset) }
        view.onUndo = { [weak self] in self?.viewModel.undo(); self?.refresh() }
        view.onRedo = { [weak self] in self?.viewModel.redo(); self?.refresh() }
        view.onDeleteSelection = { [weak self] in self?.viewModel.deleteSelection(); self?.refresh() }
        view.onLookUpWord = { [weak self] word in self?.onLookUpWord?(word) }
        view.onRegionChanged = { [weak self] rect in self?.regionChanged(rect) }
        view.onFinishedText = { [weak self] in self?.viewModel.selectTool(.select); self?.refresh() }
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
    }

    /// Host a looked-up word's Panel above the overlay. The overlay sits at the
    /// shield window level (above the menu bar/Dock), so a plain floating Panel
    /// would open behind it; as a child window it renders above, and still
    /// dismisses on resign when the user clicks back onto the overlay.
    func placePanelAbove(_ panelWindow: NSWindow) {
        guard panelWindow.parent !== window else { return }
        window.addChildWindow(panelWindow, ordered: .above)
    }

    // MARK: - Region → markup

    private func regionCommitted(_ rect: CGRect) {
        if toolbar == nil { buildToolbar() }
        positionToolbar(for: rect)
        toolbar?.orderFront(nil)
        refresh()
        scheduleRecognition()
    }

    /// The region was resized or moved: keep the toolbar by it and re-OCR.
    private func regionChanged(_ rect: CGRect) {
        positionToolbar(for: rect)
        scheduleRecognition()
    }

    // MARK: - Recognized words (OCR the region into clickable hit areas)

    /// OCR the current region off the main thread (debounced) and place each
    /// clickable Recognized word at its on-Capture position. Called when the
    /// region is committed, and (once resize lands in #18) whenever it changes.
    private func scheduleRecognition() {
        recognizeWork?.cancel()
        guard let region = view.regionRect else {
            view.words = []
            viewModel.setRecognizedText("")
            return
        }
        let pixels = CaptureGeometry.pixelRect(forViewRect: region, viewHeight: frozen.frame.height, scale: frozen.scale)
        let work = DispatchWorkItem { [weak self] in
            guard let self, let cropped = self.frozen.image.cropping(to: pixels) else { return }
            let observations = self.recognizer.recognizeWords(in: cropped)
            let words = RecognizedWordExtractor.clickableWords(from: observations)
            // Full reading-order text for Copy-text, derived from the same
            // observations (kept non-de-duplicated, unlike the clickable hits).
            let text = RecognizedTextExtractor.text(from: observations)
            // Each box is normalized to the region image (bottom-left origin);
            // CaptureGeometry places it back into frozen-screen view points.
            let hits = words.map { word in
                CaptureOverlayView.WordHit(
                    text: word.text,
                    rect: CaptureGeometry.viewRect(forNormalizedBox: word.box, in: region))
            }
            DispatchQueue.main.async { [weak self] in
                self?.view.words = hits
                self?.viewModel.setRecognizedText(text)
            }
        }
        recognizeWork = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    // MARK: - Markup edits

    private func commitMark(_ kind: MarkupObject.Kind) {
        viewModel.addObject(MarkupObject(kind: kind, style: viewModel.defaultStyle))
        refresh()
    }

    private func moveMark(_ id: UUID, by offset: CGSize) {
        viewModel.select(objectID: id)
        viewModel.moveSelection(by: offset)
        refresh()
    }

    private func refresh() {
        view.objects = viewModel.document.objects
        view.selectedID = viewModel.selectedObjectID
        view.tool = viewModel.currentTool
        view.activeStyle = viewModel.defaultStyle
        view.currentEmoji = viewModel.currentEmoji
        for (tool, button) in toolButtons { button.isActive = tool == viewModel.currentTool }
        // Ring the swatch and width dot that match the active style.
        let style = viewModel.defaultStyle
        for swatch in swatchButtons { swatch.isSelectedSwatch = swatch.color == style.stroke }
        for dot in widthButtons { dot.isSelectedWidth = dot.width == style.lineWidth }
    }

    // MARK: - Toolbar actions

    @objc private func toolTapped(_ sender: NSButton) {
        guard let tool = toolButtons.first(where: { $0.value === sender })?.key else { return }
        viewModel.selectTool(tool)
        refresh()
    }

    /// Common reaction/pointer emoji for the picker.
    private static let emojiChoices = ["👍", "✅", "❌", "⭐️", "❤️", "🔥", "⚠️", "➡️",
                                       "⬇️", "💡", "❓", "📌", "🎉", "👀", "🚀", "😀"]

    private func makeEmojiButton() -> ToolButton {
        let button = ToolButton(symbol: "face.smiling", tooltip: "Emoji")
        button.target = self
        button.action = #selector(emojiTapped(_:))
        toolButtons[.emoji] = button
        return button
    }

    /// Tapping the Emoji tool opens a small picker; choosing an emoji selects the
    /// Emoji tool, after which a click on the Capture stamps it.
    @objc private func emojiTapped(_ sender: NSButton) {
        let menu = NSMenu()
        let size = NSFont.systemFontSize * 1.4
        for emoji in Self.emojiChoices {
            let item = NSMenuItem(title: emoji, action: #selector(emojiPicked(_:)), keyEquivalent: "")
            item.target = self
            item.attributedTitle = NSAttributedString(
                string: emoji, attributes: [.font: NSFont.systemFont(ofSize: size)])
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc private func emojiPicked(_ sender: NSMenuItem) {
        viewModel.setCurrentEmoji(sender.title)
        viewModel.selectTool(.emoji)
        refresh()
    }

    @objc private func undoTapped() { viewModel.undo(); refresh() }
    @objc private func redoTapped() { viewModel.redo(); refresh() }
    @objc private func deleteTapped() { viewModel.deleteSelection(); refresh() }
    @objc private func copyTapped() { copyAndClose() }
    @objc private func copyTextTapped() {
        // Plain text, not the image — and a beep when OCR found nothing, rather
        // than silently clearing the clipboard.
        guard case .copyText(let text) = viewModel.copyText(), !text.isEmpty else {
            NSSound.beep()
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        close() // a finishing action: closing the overlay is the "done" feedback, like Copy image
    }
    @objc private func saveTapped() { saveAndClose() }
    @objc private func cancelTapped() { close() }

    /// Pick a stroke colour from the strip: restyle the selection if there is one,
    /// otherwise set the ink for the next mark — keeping the current width/size.
    @objc private func swatchTapped(_ sender: SwatchButton) {
        let style = viewModel.defaultStyle
        viewModel.setStyle(MarkupStyle(stroke: sender.color, lineWidth: style.lineWidth, fontSize: style.fontSize))
        refresh()
    }

    /// Pick a stroke width from the strip, keeping the current ink/size.
    @objc private func widthTapped(_ sender: WidthDotButton) {
        let style = viewModel.defaultStyle
        viewModel.setStyle(MarkupStyle(stroke: style.stroke, lineWidth: sender.width, fontSize: style.fontSize))
        refresh()
    }

    // MARK: - Terminal actions

    private func copyAndClose() {
        guard let region = view.regionRect,
              let png = MarkupRenderer.pngData(image: view.frozenImage, objects: viewModel.document.objects,
                                               region: region, scale: frozen.scale) else {
            NSSound.beep()
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        close()
    }

    private func saveAndClose() {
        guard let region = view.regionRect,
              let png = MarkupRenderer.pngData(image: view.frozenImage, objects: viewModel.document.objects,
                                               region: region, scale: frozen.scale) else {
            NSSound.beep()
            return
        }
        let folder = saveLocation.folder()
        let url = folder.appendingPathComponent(captureFilename(date: Date()))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: url)
            close() // drop the shield overlay first so Finder comes forward
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            NSSound.beep()
        }
    }

    // MARK: - Scroll capture (ADR 0004 — non-in-place, user-driven scroll)

    @objc private func scrollCaptureTapped() { startScrollCapture() }

    /// Drop the frozen overlay so the real, scrollable content shows, keep the
    /// Main Box drawn at the same screen coordinates, and grab + stitch frames as
    /// the user scrolls — feeding each new stitch live to the Scroll Preview pane.
    /// Copy/Save on the pane finalize (→ done); Esc cancels and brings the overlay
    /// back.
    private func startScrollCapture() {
        guard let regionView = view.regionRect, let displayID = frozen.screen.displayID else {
            NSSound.beep()
            return
        }
        let regionScreen = window.convertToScreen(regionView)
        scrollCancelled = false

        toolbar?.orderOut(nil)
        window.orderOut(nil)
        showScrollGuide(over: regionScreen)
        installScrollStopMonitors()

        let pane = ScrollPreviewPane(mainBox: regionScreen, screen: frozen.screen,
                                     scale: frozen.scale, saveLocation: saveLocation)
        pane.onFinish = { [weak self] in self?.scrollDriver?.stop() } // Copy/Save = done
        pane.onCancel = { [weak self] in // X button = Esc
            self?.scrollCancelled = true
            self?.scrollDriver?.stop()
        }
        pane.show()
        scrollPane = pane

        let driver = ScrollCaptureDriver(region: regionScreen, screen: frozen.screen,
                                         displayID: displayID, scale: frozen.scale)
        scrollDriver = driver
        driver.run(onFrame: { [weak self] image in
            self?.scrollPane?.update(image: image)
        }, completion: { [weak self] image in
            guard let self else { return }
            let cancelled = self.scrollCancelled
            self.endScrollCapture()
            if cancelled || image == nil {
                if !cancelled { NSSound.beep() } // nothing usable captured
                self.window.makeKeyAndOrderFront(nil) // bring the overlay back
                self.toolbar?.orderFront(nil)
            } else {
                // Finished via Copy/Save — the pane already acted; dismiss capture.
                self.close()
            }
        })
    }

    private func endScrollCapture() {
        scrollDriver = nil
        scrollStopMonitors.forEach(NSEvent.removeMonitor)
        scrollStopMonitors = []
        scrollGuide?.orderOut(nil); scrollGuide = nil
        scrollPane?.close(); scrollPane = nil
    }

    /// A click-through outline over the region with the "Scroll the page" prompt;
    /// it ignores the mouse so scrolls pass through to the content beneath.
    private func showScrollGuide(over regionScreen: CGRect) {
        let panel = NSPanel(contentRect: regionScreen,
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        let guide = ScrollGuideView(frame: NSRect(origin: .zero, size: regionScreen.size))
        guide.autoresizingMask = [.width, .height]
        panel.contentView = guide
        panel.orderFrontRegardless()
        scrollGuide = panel
    }

    /// Esc cancels the run and keeps nothing (ADR 0004); the driver stops and the
    /// overlay comes back. Copy/Save on the Scroll Preview are the "done" path.
    private func installScrollStopMonitors() {
        let cancel: () -> Void = { [weak self] in
            self?.scrollCancelled = true
            self?.scrollDriver?.stop()
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 { cancel() } // Esc
            return event
        }
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == 53 { cancel() }
        }
        scrollStopMonitors = [local, global].compactMap { $0 }
    }

    private func close() {
        endScrollCapture()
        // Un-parent every child (toolbar, and any looked-up Panel) so they
        // aren't tied to the overlay once it goes away.
        window.childWindows?.forEach { window.removeChildWindow($0) }
        toolbar?.orderOut(nil)
        window.orderOut(nil)
        onClosed?()
    }

    // MARK: - Toolbar chrome

    private func buildToolbar() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: Self.toolbarHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true

        let bar = NSVisualEffectView()
        bar.material = .menu
        bar.blendingMode = .behindWindow
        bar.state = .active
        bar.wantsLayer = true
        bar.layer?.cornerRadius = ToolbarStyle.cornerRadius
        bar.layer?.masksToBounds = true
        bar.layer?.borderWidth = 0.5
        bar.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.4).cgColor
        bar.translatesAutoresizingMaskIntoConstraints = false

        // Reference layout (#28): shapes → emoji → arrow → pen → highlighter →
        // pixelate → text → copy-text. The emoji button is inserted after the
        // shapes; it opens the picker rather than just selecting the tool.
        let tools: [(MarkupTool, String, String)] = [
            (.select, "cursorarrow", "Select"),
            (.rectangle, "rectangle", "Rectangle"),
            (.ellipse, "circle", "Ellipse"),
            (.arrow, "arrow.up.right", "Arrow"),
            (.freehand, "pencil.tip", "Pen"),
            (.highlight, "highlighter", "Highlighter"),
            (.blur, "square.grid.3x3", "Blur / redact"),
            (.text, "textformat", "Text"),
        ]
        toolButtons = [:]
        var toolViews: [NSView] = tools.map { tool, symbol, tooltip in
            let button = ToolButton(symbol: symbol, tooltip: tooltip)
            button.target = self
            button.action = #selector(toolTapped(_:))
            toolButtons[tool] = button
            return button
        }
        toolViews.insert(makeEmojiButton(), at: 3) // after Select, Rectangle, Ellipse

        let undo = makeButton(symbol: "arrow.uturn.backward", tooltip: "Undo", action: #selector(undoTapped))
        let redo = makeButton(symbol: "arrow.uturn.forward", tooltip: "Redo", action: #selector(redoTapped))
        let delete = makeButton(symbol: "trash", tooltip: "Delete", action: #selector(deleteTapped))

        let scrollCapture = makeButton(symbol: "arrow.up.and.down", tooltip: "Scroll capture", action: #selector(scrollCaptureTapped))

        // The finishing actions — every one of these ends the capture (Copy text and
        // Copy image close after copying; Save closes after writing). A faint tray
        // groups them so it reads at a glance as the "done" zone, set apart from the
        // tools/edit buttons to its left. Monochrome line icons keep it calm. Cancel
        // sits just outside the tray as the discard counterpart, marked by its red.
        let copyText = makeButton(symbol: "doc.plaintext", tooltip: "Copy recognized text", action: #selector(copyTextTapped))
        let copy = makeButton(symbol: "doc.on.clipboard", tooltip: "Copy to clipboard", action: #selector(copyTapped))
        let save = makeButton(symbol: "square.and.arrow.down", tooltip: "Save to folder", action: #selector(saveTapped))
        let finishTray = makeFinishTray([copyText, copy, save])

        let cancel = makeButton(symbol: "xmark", tooltip: "Cancel", action: #selector(cancelTapped))
        cancel.contentTintColor = ToolbarStyle.destructive

        let editDivider = divider()
        let row = NSStackView(views: toolViews + [scrollCapture, editDivider, undo, redo, delete,
                                                  finishTray, cancel])
        row.orientation = .horizontal
        row.spacing = ToolbarStyle.rowSpacing
        let groupGap: CGFloat = 14
        row.setCustomSpacing(groupGap, after: scrollCapture)
        row.setCustomSpacing(groupGap, after: editDivider)
        row.setCustomSpacing(18, after: delete) // wider gap → the finish zone reads apart
        row.setCustomSpacing(10, after: finishTray)

        let strip = buildStyleStrip()
        let column = NSStackView(views: [row, strip])
        column.orientation = .vertical
        // Centre both rows so the bar keeps equal left/right insets (a `.leading`
        // column silently drops the trailing edgeInset for the widest row, leaving
        // the Cancel button flush against the right edge). The strip is left-aligned
        // separately: it spans the row's width and packs its content to the left.
        column.alignment = .centerX
        column.spacing = 10
        column.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        column.translatesAutoresizingMaskIntoConstraints = false
        strip.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true

        bar.addSubview(column)
        panel.contentView = bar
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            column.topAnchor.constraint(equalTo: bar.topAnchor),
            column.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
        ])
        panel.setContentSize(column.fittingSize)

        window.addChildWindow(panel, ordered: .above)
        toolbar = panel
    }

    /// The persistent ink + width strip: width-preset dots then the colour swatches,
    /// all from `StylePresets`, the single source of truth.
    private func buildStyleStrip() -> NSStackView {
        widthButtons = StylePresets.widths.map { width in
            WidthDotButton(width: width, target: self, action: #selector(widthTapped(_:)))
        }
        swatchButtons = StylePresets.colors.map { color in
            SwatchButton(color: color, diameter: 22, target: self, action: #selector(swatchTapped(_:)))
        }
        // Width presets then colour swatches. The strip is stretched to the tool
        // row's width; `.equalSpacing` spreads the boxes edge-to-edge with one even
        // gap, so the row fills the bar — leftmost dot under the first tool, last
        // swatch under Cancel — with no empty tail.
        let strip = NSStackView(views: widthButtons + swatchButtons)
        strip.orientation = .horizontal
        strip.spacing = 8 // minimum gap; equalSpacing widens it evenly to fill
        strip.distribution = .equalSpacing
        return strip
    }

    /// Place the toolbar just below the region (above it when there is no room),
    /// horizontally centered on the region and clamped to the display.
    private func positionToolbar(for regionView: CGRect) {
        guard let toolbar else { return }
        let size = toolbar.frame.size
        let screenRegion = window.convertToScreen(regionView)
        let display = frozen.frame

        var x = screenRegion.midX - size.width / 2
        x = min(max(x, display.minX + 8), display.maxX - size.width - 8)

        var y = screenRegion.minY - Self.toolbarGap - size.height // below (visually lower)
        if y < display.minY + 8 {
            y = screenRegion.maxY + Self.toolbarGap // no room: above
        }
        y = min(y, display.maxY - size.height - 8)
        toolbar.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func makeButton(symbol: String, tooltip: String, action: Selector?) -> NSButton {
        let button = NSButton()
        button.image = ToolbarStyle.icon(symbol, tooltip)
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = tooltip
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: ToolbarStyle.buttonSize).isActive = true
        button.heightAnchor.constraint(equalToConstant: ToolbarStyle.buttonSize).isActive = true
        return button
    }

    private func divider() -> NSView {
        let line = DynamicLayerView()
        line.fillColor = .separatorColor
        line.translatesAutoresizingMaskIntoConstraints = false
        line.widthAnchor.constraint(equalToConstant: 1).isActive = true
        line.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return line
    }

    /// A faint rounded tray that groups the finishing actions into a "done" zone —
    /// clicking any button inside ends the capture. The tray is exactly button-tall
    /// (with horizontal padding) so it does not change the row height.
    private func makeFinishTray(_ buttons: [NSView]) -> NSView {
        let stack = NSStackView(views: buttons)
        stack.orientation = .horizontal
        stack.spacing = ToolbarStyle.rowSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false

        let tray = DynamicLayerView()
        tray.fillColor = ToolbarStyle.finishTray
        tray.cornerRadius = 9
        tray.translatesAutoresizingMaskIntoConstraints = false
        tray.addSubview(stack)
        let pad: CGFloat = 6
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: tray.leadingAnchor, constant: pad),
            stack.trailingAnchor.constraint(equalTo: tray.trailingAnchor, constant: -pad),
            stack.topAnchor.constraint(equalTo: tray.topAnchor),
            stack.bottomAnchor.constraint(equalTo: tray.bottomAnchor),
        ])
        return tray
    }
}

/// A borderless window must opt in to becoming key, or it can never take the
/// keyboard for Esc/Return and the Markup edit shortcuts.
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Draws the frozen still dimmed, with the bright Capture region punched out of
/// the dim, then the Markup over it (clipped to the region). Turns a drag into a
/// `RegionSelection` before a region is committed, and into Markup edits after.
/// All geometry is in view points (frozen-screen space, bottom-left origin);
/// mapping to image pixels for the flatten lives in the controller/renderer.
final class CaptureOverlayView: NSView, NSTextFieldDelegate {
    private let frozen: FrozenDisplay
    let frozenImage: NSImage

    /// The committed Capture region, or `nil` until the first drag completes.
    private var committedRect: CGRect?
    var regionRect: CGRect? { committedRect }

    // Markup state, pushed in by the controller (one source of truth).
    var objects: [MarkupObject] = [] { didSet { needsDisplay = true } }
    var selectedID: UUID? { didSet { needsDisplay = true } }
    var tool: MarkupTool = .select
    var activeStyle = MarkupStyle()
    /// The emoji the Emoji tool stamps, pushed in by the controller.
    var currentEmoji = "👍"

    /// A clickable Recognized word and its hit area in frozen-screen view points.
    struct WordHit { var text: String; var rect: CGRect }
    var words: [WordHit] = [] { didSet { hoveredWord = nil; needsDisplay = true } }
    private var hoveredWord: Int?

    // Region-drag state (pre-commit).
    private var regionDragStart: CGPoint?
    private var liveRegion: RegionSelection?

    // Region resize/move state (post-commit, Select tool).
    private var resizingHandle: RegionSelection.Handle?
    private var movingRegion = false
    private var regionMoveStart: CGPoint?
    private var regionMoveOrigin: CGRect?
    private static let handleTolerance: CGFloat = 12
    private static let handleSize: CGFloat = 8

    // Markup-drag state (post-commit).
    private var markDragStart: CGPoint?
    private var strokePoints: [CGPoint] = []
    private var pendingKind: MarkupObject.Kind?
    private var movingID: UUID?
    private var moveOffset: CGSize = .zero
    private var textField: NSTextField?
    private var textOriginView: CGPoint?

    // Callbacks to the controller.
    var onRegionCommitted: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    var onConfirmCopy: (() -> Void)?
    var onCommitMark: ((MarkupObject.Kind) -> Void)?
    var onSelectMark: ((UUID?) -> Void)?
    var onMoveMark: ((UUID, CGSize) -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onDeleteSelection: (() -> Void)?
    /// A Recognized word was clicked — look it up in the Panel.
    var onLookUpWord: ((String) -> Void)?
    /// The region was resized or moved — reposition the toolbar and re-OCR.
    var onRegionChanged: ((CGRect) -> Void)?
    /// A text label finished (committed or dismissed) — revert to the Select tool.
    var onFinishedText: (() -> Void)?

    private static let dimAlpha: CGFloat = 0.45

    init(frozen: FrozenDisplay) {
        self.frozen = frozen
        self.frozenImage = NSImage(cgImage: frozen.image, size: frozen.frame.size)
        super.init(frame: NSRect(origin: .zero, size: frozen.frame.size))
        wantsLayer = true
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { false } // bottom-left, matching screen points
    override var acceptsFirstResponder: Bool { true }
    // Register a click even when the click is what activates the overlay (e.g.
    // clicking a word while the Panel is key), so the click isn't swallowed.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Recognized words are clickable only in the default Select tool — a drawing
    /// tool means the user is marking up, not looking words up.
    private var wordsAreClickable: Bool { isMarkupActive && tool == .select }

    private func wordIndex(at point: CGPoint) -> Int? {
        guard wordsAreClickable else { return nil }
        return words.lastIndex { $0.rect.contains(point) }
    }

    private var isMarkupActive: Bool { committedRect != nil }

    private var shownRect: CGRect? {
        if let live = liveRegion, !live.isEmpty { return live.rect }
        return committedRect
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        frozenImage.draw(in: bounds)

        NSColor.black.withAlphaComponent(Self.dimAlpha).setFill()
        if let rect = shownRect {
            let dim = NSBezierPath(rect: bounds)
            dim.append(NSBezierPath(rect: rect))
            dim.windingRule = .evenOdd
            dim.fill()
        } else {
            NSBezierPath(rect: bounds).fill()
        }

        // Markup is clipped to the Capture region, so it reads as part of the
        // shot — anything outside is dropped, matching the flattened output.
        if let rect = committedRect {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: rect).addClip()
            // Highlight the hovered Recognized word so it reads as clickable.
            if let index = hoveredWord, words.indices.contains(index) {
                let pill = words[index].rect.insetBy(dx: -3, dy: -2)
                Palette.accent.withAlphaComponent(0.22).setFill()
                NSBezierPath(roundedRect: pill, xRadius: 4, yRadius: 4).fill()
            }
            for object in objects {
                MarkupDrawing.draw(object.id == movingID ? object.translated(by: moveOffset) : object, image: frozenImage)
            }
            if let pendingKind {
                MarkupDrawing.draw(MarkupObject(kind: pendingKind, style: activeStyle), image: frozenImage)
            }
            NSGraphicsContext.restoreGraphicsState()
        }

        if let rect = shownRect {
            Palette.accent.setStroke()
            let border = NSBezierPath(rect: rect)
            border.lineWidth = 1.5
            border.stroke()
        }

        // Resize handles, grabbable only in the Select tool, once committed.
        if let rect = committedRect, tool == .select, liveRegion == nil {
            drawRegionHandles(rect)
        }

        if let selected = objects.first(where: { $0.id == selectedID }) {
            let shown = selected.id == movingID ? selected.translated(by: moveOffset) : selected
            drawSelectionHandles(around: shown.bounds)
        }

        if !isMarkupActive { drawHint() }
    }

    private func drawSelectionHandles(around rect: CGRect) {
        let outline = NSBezierPath(rect: rect.insetBy(dx: -3, dy: -3))
        outline.lineWidth = 1
        NSColor.selectedControlColor.setStroke()
        outline.setLineDash([4, 3], count: 2, phase: 0)
        outline.stroke()
    }

    private func drawRegionHandles(_ rect: CGRect) {
        let selection = RegionSelection(bounds: bounds, rect: rect)
        let size = Self.handleSize
        for handle in RegionSelection.Handle.allCases {
            let center = selection.handlePoint(handle)
            let box = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
            NSColor.white.setFill()
            NSBezierPath(rect: box).fill()
            Palette.accent.setStroke()
            let outline = NSBezierPath(rect: box)
            outline.lineWidth = 1.5
            outline.stroke()
        }
    }

    private var committedSelection: RegionSelection? {
        committedRect.map { RegionSelection(bounds: bounds, rect: $0) }
    }

    private func drawHint() {
        let text = "Drag to select an area"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.quickRunSerif(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.9),
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let origin = CGPoint(x: (bounds.width - size.width) / 2, y: 40)
        let pill = CGRect(origin: origin, size: size).insetBy(dx: -14, dy: -8)
        NSColor.black.withAlphaComponent(0.5).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 8, yRadius: 8).fill()
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }

    // MARK: - Mouse

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = wordIndex(at: point)
        if index != hoveredWord {
            hoveredWord = index
            needsDisplay = true
        }
        // Cursor reads the affordance under the pointer: resize on a handle, a
        // grab hand inside the region, a finger over a word.
        if tool == .select, committedSelection?.handle(at: point, tolerance: Self.handleTolerance) != nil {
            NSCursor.crosshair.set()
        } else if index != nil {
            NSCursor.pointingHand.set()
        } else if tool == .select, committedRect?.contains(point) == true {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func mouseDown(with event: NSEvent) {
        // An open text field: a click anywhere else commits it (discarding an
        // empty one) and returns to the Select tool — the click is swallowed.
        if textField != nil {
            endText()
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        guard let region = committedSelection else {
            regionDragStart = point
            liveRegion = nil
            needsDisplay = true
            return
        }
        // The pure resolver decides what the click means; the view only carries
        // out the verdict and holds the resulting drag state.
        switch EditorInteraction.resolve(
            tool: tool, point: point, region: region,
            handleTolerance: Self.handleTolerance,
            wordRects: wordsAreClickable ? words.map(\.rect) : [],
            marks: objects
        ) {
        case .resizeRegion(let handle):
            resizingHandle = handle
            words = [] // boxes are stale until OCR re-runs for the new region
        case .lookUpWord(let index):
            onLookUpWord?(words[index].text)
        case .selectMark(let id):
            onSelectMark?(id)
            movingID = id
            markDragStart = point
            moveOffset = .zero
        case .moveRegion:
            onSelectMark?(nil)
            movingRegion = true
            regionMoveStart = point
            regionMoveOrigin = region.rect
        case .deselect:
            onSelectMark?(nil)
            markDragStart = nil
            movingID = nil
        case .beginText:
            beginText(at: point)
        case .placeEmoji:
            placeEmoji(at: point)
        case .drawMarkup:
            markDragStart = point
            strokePoints = [point]
            updatePending(to: point)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let handle = resizingHandle, let rect = committedRect {
            apply(RegionSelection(bounds: bounds, rect: rect).resized(handle, to: point))
            return
        }
        if movingRegion, let start = regionMoveStart, let origin = regionMoveOrigin {
            let offset = CGSize(width: point.x - start.x, height: point.y - start.y)
            apply(RegionSelection(bounds: bounds, rect: origin).moved(by: offset))
            return
        }
        if isMarkupActive {
            markupMouseDragged(to: point)
        } else if let start = regionDragStart {
            liveRegion = RegionSelection.fromDrag(from: start, to: point, in: bounds)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if resizingHandle != nil || movingRegion {
            resizingHandle = nil
            movingRegion = false
            regionMoveStart = nil
            regionMoveOrigin = nil
            if let rect = committedRect { onRegionChanged?(rect) } // settle → re-OCR
            needsDisplay = true
            return
        }
        if isMarkupActive {
            markupMouseUp()
        } else {
            if let region = liveRegion, !region.isEmpty {
                committedRect = region.rect
                onRegionCommitted?(region.rect)
            } else if committedRect == nil {
                onCancel?()
            }
            regionDragStart = nil
            liveRegion = nil
        }
        needsDisplay = true
    }

    /// Adopt a resized/moved region and tell the controller live (so the toolbar
    /// tracks it); OCR is rescheduled and debounced there.
    private func apply(_ selection: RegionSelection) {
        committedRect = selection.rect
        onRegionChanged?(selection.rect)
        needsDisplay = true
    }

    // MARK: - Markup mouse (frozen-screen space; identity mapping)

    private func markupMouseDragged(to point: CGPoint) {
        switch tool {
        case .select where movingID != nil:
            if let start = markDragStart {
                moveOffset = CGSize(width: point.x - start.x, height: point.y - start.y)
            }
        case .freehand, .highlight:
            strokePoints.append(point)
            updatePending(to: point)
        case .rectangle, .ellipse, .arrow, .blur:
            updatePending(to: point)
        default:
            break
        }
    }

    private func markupMouseUp() {
        switch tool {
        case .select:
            if let id = movingID, moveOffset != .zero { onMoveMark?(id, moveOffset) }
        case .rectangle, .ellipse, .arrow, .freehand, .highlight, .blur:
            if let kind = pendingKind, Self.isCommittable(kind) { onCommitMark?(kind) }
        case .text, .emoji:
            break // placed on mouse-down, not on a drag
        }
        markDragStart = nil
        strokePoints = []
        pendingKind = nil
        movingID = nil
        moveOffset = .zero
    }

    private func updatePending(to point: CGPoint) {
        guard let start = markDragStart else { return }
        switch tool {
        case .rectangle: pendingKind = .rectangle(spanRect(start, point))
        case .ellipse: pendingKind = .ellipse(spanRect(start, point))
        case .blur: pendingKind = .blur(spanRect(start, point))
        case .arrow: pendingKind = .arrow(from: start, to: point)
        case .freehand: pendingKind = .freehand(strokePoints)
        case .highlight: pendingKind = .highlight(strokePoints)
        default: break
        }
    }

    private func spanRect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    private static func isCommittable(_ kind: MarkupObject.Kind) -> Bool {
        switch kind {
        case .rectangle(let rect), .ellipse(let rect), .blur(let rect):
            return rect.width > 2 && rect.height > 2
        case .arrow(let from, let to):
            return hypot(to.x - from.x, to.y - from.y) > 4
        case .freehand(let points), .highlight(let points):
            return points.count >= 2
        case .text, .emoji:
            return true
        }
    }

    // MARK: - Emoji

    /// Stamp the current emoji centred on `point`, sized by the style's font size,
    /// and commit it immediately (no editable field, unlike text).
    private func placeEmoji(at point: CGPoint) {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: activeStyle.fontSize)]
        let size = (currentEmoji as NSString).size(withAttributes: attributes)
        let origin = CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
        onCommitMark?(.emoji(currentEmoji, CGRect(origin: origin, size: size)))
    }

    // MARK: - Text entry

    private func beginText(at point: CGPoint) {
        endText()
        let field = NSTextField()
        field.font = .boldSystemFont(ofSize: activeStyle.fontSize)
        field.textColor = NSColor(activeStyle.stroke)
        field.isBordered = false
        field.drawsBackground = true
        field.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.85)
        field.focusRingType = .none
        field.delegate = self
        let height = max(24, activeStyle.fontSize * 1.4)
        field.frame = CGRect(x: point.x, y: point.y, width: 220, height: height)
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
        textOriginView = point
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        endText()
    }

    private func endText() {
        guard let field = textField, let origin = textOriginView else { return }
        let string = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        textField = nil
        textOriginView = nil
        field.removeFromSuperview()
        window?.makeFirstResponder(self)

        if !string.isEmpty {
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: activeStyle.fontSize)]
            let size = (string as NSString).size(withAttributes: attributes)
            onCommitMark?(.text(string, CGRect(origin: origin, size: size)))
        }
        // Placing (or abandoning) a label returns to the pointer (Select) tool.
        onFinishedText?()
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        let command = event.modifierFlags.contains(.command)
        let shift = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 53: // Esc
            onCancel?()
        case 36, 76: // Return / keypad Enter — confirm (copy) once a region exists
            committedRect == nil ? NSSound.beep() : onConfirmCopy?()
        case 6 where command: // Z
            shift ? onRedo?() : onUndo?()
        case 51, 117: // delete / forward delete (the `where` would guard only 117)
            guard selectedID != nil else { super.keyDown(with: event); return }
            onDeleteSelection?()
        default:
            super.keyDown(with: event)
        }
    }
}
