import AppKit
import QuickRunKit

/// Shared look for the floating toolbars (Editor and Scroll Preview): one icon
/// weight/size and one card radius, so the two bars read as the same family.
public enum ToolbarStyle {
    /// Slightly larger, medium-weight glyphs — crisper and more legible than the
    /// default template size, the main lift over the old toolbar.
    static let symbol = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
    /// The rounded-card corner radius of the bar itself.
    public static let cornerRadius: CGFloat = 13
    /// Buttons are square, so the active-tool chip is a square and every icon has
    /// equal margins on all four sides.
    public static let buttonSize: CGFloat = 30
    public static let rowSpacing: CGFloat = 8
    /// Corner radius of the square selection chip — shared by the active-tool chip
    /// and the selected swatch/width chips, so "selected" is one shape everywhere.
    /// Matches `fieldRadius` so a selected end-item nests flush in its field with no
    /// lighter sliver at the corner.
    static let chipRadius: CGFloat = 9
    /// Uniform glyph footprint (largest dimension) inside the square button. SF
    /// Symbols render at very different sizes for one point size — a tall glyph
    /// would otherwise overflow the 30pt button (NSButton does not clip its image),
    /// spill out of the selection chip, and read as a different size. Normalising
    /// every glyph to this box makes all icons one size and keeps each fully inside
    /// its square chip.
    static let glyphBox: CGFloat = 17

    /// The toolbar's chrome accent — a neutral slate (graphite) for the active-tool
    /// chip, the swatch/width selection ring, and the selected width dot. Kept local
    /// to the toolbar rather than the app-wide seal-red `Palette.accent`, so the
    /// chrome reads quiet and system-clean while the brand red stays on the Panel.
    /// Resolves lighter in dark mode so the slate is legible on both bar materials.
    static let selection = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.66, green: 0.70, blue: 0.76, alpha: 1)
            : NSColor(red: 0.30, green: 0.33, blue: 0.38, alpha: 1)
    }

    /// A muted brick red for the discard/Cancel action — calmer than `systemRed`,
    /// so it still signals "destructive" without shouting against the graphite chrome.
    public static let destructive = NSColor(red: 0.80, green: 0.36, blue: 0.34, alpha: 1)

    /// Graphite wash behind a segment field — the recessed pill that brackets each
    /// functional group (tools · scroll-capture · history · finish). One opacity for
    /// every field so the grouping reads as the bar's structure. A contrast ladder
    /// keeps the layers legible: field (this) < `finishField` (the emphasised "done"
    /// zone) < `selectionChip` (the active-tool / selected chip that must still pop
    /// above its field).
    static var segmentField: NSColor { selection.withAlphaComponent(0.14) }

    /// A stronger wash for the finishing-actions field — the "done" zone reads a notch
    /// heavier than the other fields so the eye lands on it as the way out.
    static var finishField: NSColor { selection.withAlphaComponent(0.22) }

    /// The selected-state chip behind the active tool, the selected swatch, and the
    /// selected width dot — one shape *and* weight everywhere "selected" appears, sat
    /// at the top of the field contrast ladder so it pops above the tools field.
    static var selectionChip: NSColor { selection.withAlphaComponent(0.26) }

    /// Corner radius of a segment field's recessed pill.
    static let fieldRadius: CGFloat = 9

    /// A toolbar icon at the shared weight, normalised to a uniform footprint so
    /// every glyph is one size and stays inside its square chip.
    public static func icon(_ name: String, _ accessibility: String) -> NSImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: accessibility)?
            .withSymbolConfiguration(symbol) else { return nil }
        let natural = image.size
        guard natural.width > 0, natural.height > 0 else { return image }
        let scale = glyphBox / max(natural.width, natural.height)
        image.size = NSSize(width: natural.width * scale, height: natural.height * scale)
        return image
    }
}

/// A toolbar tool button that wears a seal-red pill while it is the active tool,
/// so the held tool reads at a glance instead of as a faint tint.
public final class ToolButton: NSButton {
    public var isActive = false { didSet { updateAppearance() } }

    public init(symbol: String, tooltip: String) {
        super.init(frame: .zero)
        image = ToolbarStyle.icon(symbol, tooltip)
        imagePosition = .imageOnly
        isBordered = false
        setButtonType(.momentaryChange)
        toolTip = tooltip
        wantsLayer = true
        layer?.cornerRadius = ToolbarStyle.chipRadius
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: ToolbarStyle.buttonSize).isActive = true
        heightAnchor.constraint(equalToConstant: ToolbarStyle.buttonSize).isActive = true
        updateAppearance()
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance() // re-resolve the chip's layer colour for the new light/dark
    }

    private func updateAppearance() {
        // `selection` is a dynamic colour; a CALayer colour does not auto-resolve, so
        // bake it against this view's effective appearance (also re-run on mode change).
        var chip = NSColor.clear.cgColor
        if isActive {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                chip = ToolbarStyle.selectionChip.cgColor
            }
        }
        layer?.backgroundColor = chip
        contentTintColor = isActive ? ToolbarStyle.selection : .secondaryLabelColor
    }
}

/// A round colour swatch — the toolbar's current-ink chip and each preset in the
/// colour popover.
public final class SwatchButton: NSButton {
    public var color: RGBAColor { didSet { needsDisplay = true } }
    public var isSelectedSwatch = false { didSet { needsDisplay = true } }
    private let circleDiameter: CGFloat

    public init(color: RGBAColor, diameter: CGFloat, target: AnyObject?, action: Selector?) {
        self.color = color
        self.circleDiameter = diameter
        super.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        title = ""
        translatesAutoresizingMaskIntoConstraints = false
        // Box matches every other toolbar button so all icons are one size and the
        // row's gaps stay even; the colour circle sits centred inside it.
        widthAnchor.constraint(equalToConstant: ToolbarStyle.buttonSize).isActive = true
        heightAnchor.constraint(equalToConstant: ToolbarStyle.buttonSize).isActive = true
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func draw(_ dirtyRect: NSRect) {
        // Selected state is a square chip, like the active-tool chip — one selection
        // shape across the whole toolbar.
        if isSelectedSwatch {
            let chip = NSBezierPath(roundedRect: bounds, xRadius: ToolbarStyle.chipRadius, yRadius: ToolbarStyle.chipRadius)
            ToolbarStyle.selectionChip.setFill()
            chip.fill()
        }
        let dot = NSBezierPath(ovalIn: NSRect(x: bounds.midX - circleDiameter / 2,
                                              y: bounds.midY - circleDiameter / 2,
                                              width: circleDiameter, height: circleDiameter))
        NSColor(color).setFill()
        dot.fill()
        // A hairline keeps white/pale inks visible against the bar.
        NSColor.separatorColor.setStroke()
        dot.lineWidth = 1
        dot.stroke()
    }
}

/// A stroke-width preset in the inline strip, drawn as a centred filled dot whose
/// size tracks the width it sets. Wears the accent ring (and accent fill) while
/// it is the active width, the swatch's counterpart for `StylePresets.widths`.
public final class WidthDotButton: NSButton {
    public let width: Double
    public var isSelectedWidth = false { didSet { needsDisplay = true } }

    public init(width: Double, target: AnyObject?, action: Selector?) {
        self.width = width
        super.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        title = ""
        toolTip = "\(Int(width)) pt"
        translatesAutoresizingMaskIntoConstraints = false
        // Same box as every other toolbar button — uniform size, even gaps.
        widthAnchor.constraint(equalToConstant: ToolbarStyle.buttonSize).isActive = true
        heightAnchor.constraint(equalToConstant: ToolbarStyle.buttonSize).isActive = true
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func draw(_ dirtyRect: NSRect) {
        if isSelectedWidth {
            let chip = NSBezierPath(roundedRect: bounds, xRadius: ToolbarStyle.chipRadius, yRadius: ToolbarStyle.chipRadius)
            ToolbarStyle.selectionChip.setFill()
            chip.fill()
        }
        let diameter = min(bounds.width - 6, CGFloat(width) + 5)
        let dot = NSBezierPath(ovalIn: CGRect(x: bounds.midX - diameter / 2,
                                              y: bounds.midY - diameter / 2,
                                              width: diameter, height: diameter))
        (isSelectedWidth ? ToolbarStyle.selection : NSColor.secondaryLabelColor).setFill()
        dot.fill()
    }
}

/// The editor toolbar's content — the segmented tool row plus the ink/width strip —
/// built once from `ToolbarStyle` + `StylePresets`. The live capture overlay
/// (`CaptureOverlayController`) builds *this* tree and wires it; the offscreen
/// snapshot drives that same overlay, so there is a single layout definition instead
/// of a hand-mirrored copy that drifts. The overlay supplies its own chrome around
/// `view` (a live `NSPanel` + `NSVisualEffectView`); the snapshot renders the same
/// `view` on a flat card — `NSVisualEffectView` blur is the one thing that cannot
/// render offscreen, so the chrome is the only part that legitimately differs.
public struct EditorToolbarContent {
    /// The non-tool buttons, keyed so a caller can wire each to its action (or leave
    /// it inert, as the snapshot does).
    public enum Action: CaseIterable {
        case scrollCapture, undo, redo, delete, copyText, copyImage, save, cancel
    }

    public let view: NSView
    public let toolButtons: [MarkupTool: ToolButton]
    public let actionButtons: [Action: NSButton]
    public let swatchButtons: [SwatchButton]
    public let widthButtons: [WidthDotButton]

    /// Visual order of the tool segment (#28). Emoji sits after the shapes; it opens a
    /// picker rather than just selecting, but it is still a tool button here — the
    /// caller wires its picker action.
    private static let tools: [(MarkupTool, String, String)] = [
        (.select, "cursorarrow", "Select"),
        (.rectangle, "rectangle", "Rectangle"),
        (.ellipse, "circle", "Ellipse"),
        (.emoji, "face.smiling", "Emoji"),
        (.arrow, "arrow.up.right", "Arrow"),
        (.freehand, "pencil.tip", "Pen"),
        (.highlight, "highlighter", "Highlighter"),
        (.blur, "square.grid.3x3", "Blur / redact"),
        (.text, "textformat", "Text"),
    ]

    private static let actions: [(Action, String, String)] = [
        (.scrollCapture, "arrow.up.and.down", "Scroll capture"),
        (.undo, "arrow.uturn.backward", "Undo"),
        (.redo, "arrow.uturn.forward", "Redo"),
        (.delete, "trash", "Delete"),
        (.copyText, "doc.plaintext", "Copy recognized text"),
        (.copyImage, "doc.on.clipboard", "Copy to clipboard"),
        (.save, "square.and.arrow.down", "Save to folder"),
        (.cancel, "xmark", "Cancel"),
    ]

    public static func build() -> EditorToolbarContent {
        var toolButtons: [MarkupTool: ToolButton] = [:]
        let toolViews: [NSView] = tools.map { tool, symbol, tooltip in
            let button = ToolButton(symbol: symbol, tooltip: tooltip)
            toolButtons[tool] = button
            return button
        }

        var actionButtons: [Action: NSButton] = [:]
        for (action, symbol, tooltip) in actions {
            let button = actionButton(symbol: symbol, tooltip: tooltip)
            if action == .cancel { button.contentTintColor = ToolbarStyle.destructive }
            actionButtons[action] = button
        }
        func btn(_ a: Action) -> NSButton { actionButtons[a]! }

        // Each functional group rides its own recessed field. Ordered as the capture
        // workflow runs left→right: re-grab (scroll-capture) · annotate (tools) · undo
        // (history) · finish. Scroll capture is not an annotation tool — it leaves the
        // editor to re-grab a taller region (ADR 0004) — so it leads in its own field
        // instead of reading as a ninth tool. The finish field wears a heavier wash as
        // the "done" zone; cancel rides bare outside as discard, marked by its brick red.
        let captureField = segment([btn(.scrollCapture)])
        let toolsField = segment(toolViews)
        let historyField = segment([btn(.undo), btn(.redo), btn(.delete)])
        let finishField = segment([btn(.copyText), btn(.copyImage), btn(.save)], fill: ToolbarStyle.finishField)

        let row = NSStackView(views: [captureField, toolsField, historyField, finishField, btn(.cancel)])
        row.orientation = .horizontal
        row.spacing = 10
        row.setCustomSpacing(12, after: finishField) // a touch more air before discard

        // The ink strip mirrors the tool row above: the width presets ride one
        // recessed field and the colour swatches another, so "weight" and "colour"
        // read as two groups in the same segment-field language as the bar — all from
        // `StylePresets`, the single source of truth.
        let widthButtons = StylePresets.widths.map { WidthDotButton(width: $0, target: nil, action: nil) }
        let swatchButtons = StylePresets.colors.map { SwatchButton(color: $0, diameter: 22, target: nil, action: nil) }
        // The colour field carries the strip out to the tool row's full width (pinned
        // below), so its swatches spread with `.equalSpacing`; the width field keeps
        // its natural size and the two rows' edges line up.
        let widthsField = segment(widthButtons)
        let colorsField = segment(swatchButtons, distribution: .equalSpacing)
        widthsField.setContentHuggingPriority(.required, for: .horizontal)
        colorsField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let strip = NSStackView(views: [widthsField, colorsField])
        strip.orientation = .horizontal
        strip.spacing = 10
        strip.distribution = .fill

        // Centre both rows so the bar keeps equal left/right insets (a `.leading`
        // column silently drops the trailing edgeInset for the widest row).
        let column = NSStackView(views: [row, strip])
        column.orientation = .vertical
        column.alignment = .centerX
        column.spacing = 10
        column.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        column.translatesAutoresizingMaskIntoConstraints = false
        // Both rows span the same width so their left/right edges line up and the card
        // keeps equal side insets; the colour field absorbs the difference.
        strip.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true

        return EditorToolbarContent(view: column, toolButtons: toolButtons,
                                    actionButtons: actionButtons,
                                    swatchButtons: swatchButtons, widthButtons: widthButtons)
    }

    /// A plain (non-tool) toolbar button at the shared box/icon size, with no target —
    /// the caller wires the action.
    private static func actionButton(symbol: String, tooltip: String) -> NSButton {
        let button = NSButton()
        button.image = ToolbarStyle.icon(symbol, tooltip)
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = tooltip
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: ToolbarStyle.buttonSize).isActive = true
        button.heightAnchor.constraint(equalToConstant: ToolbarStyle.buttonSize).isActive = true
        return button
    }

    /// Wrap a group of buttons in a faint recessed field — the pill that brackets one
    /// functional group so the grouping reads as the bar's structure. Exactly
    /// button-tall (with horizontal padding) so it does not change the row height.
    private static func segment(_ buttons: [NSView], fill: NSColor = ToolbarStyle.segmentField,
                                distribution: NSStackView.Distribution? = nil) -> NSView {
        let stack = NSStackView(views: buttons)
        stack.orientation = .horizontal
        stack.spacing = ToolbarStyle.rowSpacing
        if let distribution { stack.distribution = distribution }
        stack.translatesAutoresizingMaskIntoConstraints = false

        let field = DynamicLayerView()
        field.fillColor = fill
        field.cornerRadius = ToolbarStyle.fieldRadius
        field.translatesAutoresizingMaskIntoConstraints = false
        field.addSubview(stack)
        // No inner pad: the field hugs its buttons so a selected item's chip sits
        // flush against the field edge — clicking the first/last item fits snugly
        // instead of leaving a sliver of field on the outside.
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: field.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: field.trailingAnchor),
            stack.topAnchor.constraint(equalTo: field.topAnchor),
            stack.bottomAnchor.constraint(equalTo: field.bottomAnchor),
        ])
        return field
    }
}
