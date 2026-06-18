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

    // Floating toolbar, shown once a region is committed.
    private var toolbar: NSPanel?
    private var toolButtons: [MarkupTool: ToolButton] = [:]
    private let colorSwatch = SwatchButton(color: .sealRed, diameter: 22, target: nil, action: nil)
    private let colorPopover = NSPopover()
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
            return
        }
        let pixels = pixelRect(for: region)
        let work = DispatchWorkItem { [weak self] in
            guard let self, let cropped = self.frozen.image.cropping(to: pixels) else { return }
            let observations = self.recognizer.recognizeWords(in: cropped)
            let words = RecognizedWordExtractor.clickableWords(from: observations)
            // Map each box (normalized to the region image, bottom-left origin)
            // into frozen-screen view points within the region.
            let hits = words.map { word in
                CaptureOverlayView.WordHit(
                    text: word.text,
                    rect: CGRect(x: region.minX + word.box.minX * region.width,
                                 y: region.minY + word.box.minY * region.height,
                                 width: word.box.width * region.width,
                                 height: word.box.height * region.height))
            }
            DispatchQueue.main.async { [weak self] in self?.view.words = hits }
        }
        recognizeWork = work
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    /// Map a region in view points (bottom-left origin) to the frozen image's
    /// pixel rect (top-left origin, native resolution).
    private func pixelRect(for region: CGRect) -> CGRect {
        let s = frozen.scale
        return CGRect(x: region.minX * s,
                      y: (frozen.frame.height - region.maxY) * s,
                      width: region.width * s,
                      height: region.height * s)
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
        for (tool, button) in toolButtons { button.isActive = tool == viewModel.currentTool }
        colorSwatch.color = viewModel.defaultStyle.stroke
    }

    // MARK: - Toolbar actions

    @objc private func toolTapped(_ sender: NSButton) {
        guard let tool = toolButtons.first(where: { $0.value === sender })?.key else { return }
        viewModel.selectTool(tool)
        refresh()
    }

    @objc private func undoTapped() { viewModel.undo(); refresh() }
    @objc private func redoTapped() { viewModel.redo(); refresh() }
    @objc private func deleteTapped() { viewModel.deleteSelection(); refresh() }
    @objc private func copyTapped() { copyAndClose() }
    @objc private func saveTapped() { saveAndClose() }
    @objc private func cancelTapped() { close() }

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
            close()
        } catch {
            NSSound.beep()
        }
    }

    private func close() {
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
        bar.layer?.cornerRadius = 10
        bar.layer?.masksToBounds = true
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

        let copy = makeButton(symbol: "checkmark.circle.fill", tooltip: "Copy to clipboard", action: #selector(copyTapped))
        copy.contentTintColor = .systemGreen
        let save = makeButton(symbol: "square.and.arrow.down", tooltip: "Save to folder", action: #selector(saveTapped))
        let cancel = makeButton(symbol: "xmark.circle.fill", tooltip: "Cancel", action: #selector(cancelTapped))
        cancel.contentTintColor = .systemRed

        let row = NSStackView(views: toolViews + [divider(), undo, redo, delete, divider(), colorSwatch,
                                                  divider(), copy, save, cancel])
        row.orientation = .horizontal
        row.spacing = 7
        row.translatesAutoresizingMaskIntoConstraints = false

        bar.addSubview(row)
        panel.contentView = bar
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -12),
            row.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            row.heightAnchor.constraint(equalToConstant: Self.toolbarHeight),
        ])
        panel.setContentSize(row.fittingSize + NSSize(width: 24, height: 0))

        window.addChildWindow(panel, ordered: .above)
        toolbar = panel
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
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = tooltip
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
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
}

private func + (lhs: NSSize, rhs: NSSize) -> NSSize {
    NSSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
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
        let point = convert(event.locationInWindow, from: nil)
        guard isMarkupActive else {
            regionDragStart = point
            liveRegion = nil
            needsDisplay = true
            return
        }
        // A region handle resizes — highest priority, so an edge near a word or
        // mark is still grabbable.
        if tool == .select, let handle = committedSelection?.handle(at: point, tolerance: Self.handleTolerance) {
            resizingHandle = handle
            words = [] // boxes are stale until OCR re-runs for the new region
            return
        }
        // A Recognized word looked up takes priority over starting a mark.
        if let index = wordIndex(at: point) {
            onLookUpWord?(words[index].text)
            return
        }
        markupMouseDown(at: point)
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

    private func markupMouseDown(at point: CGPoint) {
        switch tool {
        case .select:
            if let hit = objects.last(where: { $0.bounds.contains(point) }) {
                onSelectMark?(hit.id)
                movingID = hit.id
                markDragStart = point
                moveOffset = .zero
            } else if let rect = committedRect, rect.contains(point) {
                // Empty space inside the region → drag moves the whole region.
                onSelectMark?(nil)
                movingRegion = true
                regionMoveStart = point
                regionMoveOrigin = rect
            } else {
                // Outside the region → deselect (and the Panel closes on resign).
                onSelectMark?(nil)
                markDragStart = nil
                movingID = nil
            }
        case .text:
            beginText(at: point)
        case .rectangle, .arrow, .freehand, .highlight, .blur:
            markDragStart = point
            strokePoints = [point]
            updatePending(to: point)
        }
    }

    private func markupMouseDragged(to point: CGPoint) {
        switch tool {
        case .select where movingID != nil:
            if let start = markDragStart {
                moveOffset = CGSize(width: point.x - start.x, height: point.y - start.y)
            }
        case .freehand, .highlight:
            strokePoints.append(point)
            updatePending(to: point)
        case .rectangle, .arrow, .blur:
            updatePending(to: point)
        default:
            break
        }
    }

    private func markupMouseUp() {
        switch tool {
        case .select:
            if let id = movingID, moveOffset != .zero { onMoveMark?(id, moveOffset) }
        case .rectangle, .arrow, .freehand, .highlight, .blur:
            if let kind = pendingKind, Self.isCommittable(kind) { onCommitMark?(kind) }
        case .text:
            break
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
        case .rectangle(let rect), .blur(let rect):
            return rect.width > 2 && rect.height > 2
        case .arrow(let from, let to):
            return hypot(to.x - from.x, to.y - from.y) > 4
        case .freehand(let points), .highlight(let points):
            return points.count >= 2
        case .text:
            return true
        }
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
        guard !string.isEmpty else { return }

        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: activeStyle.fontSize)]
        let size = (string as NSString).size(withAttributes: attributes)
        onCommitMark?(.text(string, CGRect(origin: origin, size: size)))
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
