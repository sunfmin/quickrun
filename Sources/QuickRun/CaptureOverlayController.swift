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
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
    }

    // MARK: - Region → markup

    private func regionCommitted(_ rect: CGRect) {
        if toolbar == nil { buildToolbar() }
        positionToolbar(for: rect)
        toolbar?.orderFront(nil)
        refresh()
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
        if let toolbar { window.removeChildWindow(toolbar); toolbar.orderOut(nil) }
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

    // Region-drag state (pre-commit).
    private var regionDragStart: CGPoint?
    private var liveRegion: RegionSelection?

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

    private static let dimAlpha: CGFloat = 0.45

    init(frozen: FrozenDisplay) {
        self.frozen = frozen
        self.frozenImage = NSImage(cgImage: frozen.image, size: frozen.frame.size)
        super.init(frame: NSRect(origin: .zero, size: frozen.frame.size))
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { false } // bottom-left, matching screen points
    override var acceptsFirstResponder: Bool { true }

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

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isMarkupActive {
            markupMouseDown(at: point)
        } else {
            regionDragStart = point
            liveRegion = nil
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isMarkupActive {
            markupMouseDragged(to: point)
        } else if let start = regionDragStart {
            liveRegion = RegionSelection.fromDrag(from: start, to: point, in: bounds)
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
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

    // MARK: - Markup mouse (frozen-screen space; identity mapping)

    private func markupMouseDown(at point: CGPoint) {
        switch tool {
        case .select:
            if let hit = objects.last(where: { $0.bounds.contains(point) }) {
                onSelectMark?(hit.id)
                movingID = hit.id
                markDragStart = point
                moveOffset = .zero
            } else {
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
