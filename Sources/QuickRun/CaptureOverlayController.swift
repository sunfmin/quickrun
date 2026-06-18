import AppKit
import QuickRunKit

/// The Editor, redesigned as an in-place overlay (ADR 0003): a borderless,
/// full-display window showing the frozen screen dimmed, on which the user drags
/// out the Capture region right where the content sits. Later slices hang the
/// floating toolbar, in-place Markup, and clickable Recognized words off this
/// same overlay; this slice is the freeze-and-select foundation.
///
/// Terminal actions for now are keyboard-only — Return copies the committed
/// Capture and closes, Esc cancels — until #19 brings the floating toolbar.
final class CaptureOverlayController: NSObject {
    private let window: OverlayWindow
    private let view: CaptureOverlayView
    private let frozen: FrozenDisplay

    var onClosed: (() -> Void)?

    init(frozen: FrozenDisplay) {
        self.frozen = frozen
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
        // Above the menu bar and Dock so the freeze reads as the whole screen.
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.contentView = view

        view.onCancel = { [weak self] in self?.close() }
        view.onConfirm = { [weak self] in self?.confirm() }
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
    }

    private func confirm() {
        guard let image = view.croppedCaptureImage() else {
            NSSound.beep()
            return
        }
        copyToClipboard(image)
        close()
    }

    private func copyToClipboard(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            pasteboard.setData(png, forType: .png)
        } else {
            pasteboard.writeObjects([image])
        }
    }

    private func close() {
        window.orderOut(nil)
        onClosed?()
    }
}

/// A borderless window must opt in to becoming key, or it can never take the
/// keyboard for Esc/Return.
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Draws the frozen still dimmed, with the bright Capture region punched out of
/// the dim, and turns a drag into a `RegionSelection`. All geometry is in view
/// points (bottom-left origin); the mapping to image pixels for cropping is the
/// one place the Retina scale matters.
final class CaptureOverlayView: NSView {
    private let frozen: FrozenDisplay
    private let frozenImage: NSImage

    /// The region committed by the last completed drag, if any.
    private var committedRect: CGRect?
    /// The drag in progress, normalized live as the mouse moves.
    private var liveRegion: RegionSelection?
    private var dragStart: CGPoint?

    /// A pre-commit empty click (or Esc) — cancel and keep nothing.
    var onCancel: (() -> Void)?
    /// Return with a committed region — copy the Capture and close.
    var onConfirm: (() -> Void)?

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

    // The region to show right now: the live drag wins, else the committed one.
    private var shownRect: CGRect? {
        if let live = liveRegion, !live.isEmpty { return live.rect }
        return committedRect
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        frozenImage.draw(in: bounds)

        NSColor.black.withAlphaComponent(Self.dimAlpha).setFill()
        if let rect = shownRect {
            // Dim everything except the bright region (even-odd punches the hole).
            let path = NSBezierPath(rect: bounds)
            path.append(NSBezierPath(rect: rect))
            path.windingRule = .evenOdd
            path.fill()

            Palette.accent.setStroke()
            let border = NSBezierPath(rect: rect)
            border.lineWidth = 1.5
            border.stroke()
        } else {
            NSBezierPath(rect: bounds).fill()
        }

        drawHint()
    }

    private func drawHint() {
        let text = committedRect == nil
            ? "Drag to select an area"
            : "⏎  Copy    esc  Cancel"
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
        dragStart = convert(event.locationInWindow, from: nil)
        liveRegion = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        liveRegion = RegionSelection.fromDrag(from: start, to: point, in: bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil; liveRegion = nil; needsDisplay = true }
        if let region = liveRegion, !region.isEmpty {
            committedRect = region.rect
        } else if committedRect == nil {
            // A click with nothing yet selected cancels the whole capture.
            onCancel?()
        }
        // An empty click while a region is already committed is ignored.
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            onCancel?()
        case 36, 76: // Return / keypad Enter
            committedRect == nil ? NSSound.beep() : onConfirm?()
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - Cropping (the one place Retina scale matters)

    /// The committed Capture cropped from the frozen still at native resolution,
    /// or `nil` if nothing is committed.
    func croppedCaptureImage() -> NSImage? {
        guard let rect = committedRect,
              let cropped = frozen.image.cropping(to: pixelRect(for: rect)) else { return nil }
        return NSImage(cgImage: cropped, size: rect.size)
    }

    /// Map a view-point rect (bottom-left origin) to the frozen image's pixel
    /// rect (top-left origin, native resolution).
    private func pixelRect(for viewRect: CGRect) -> CGRect {
        let s = frozen.scale
        return CGRect(x: viewRect.minX * s,
                      y: (bounds.height - viewRect.maxY) * s,
                      width: viewRect.width * s,
                      height: viewRect.height * s)
    }
}
