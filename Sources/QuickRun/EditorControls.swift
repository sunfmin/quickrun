import AppKit
import QuickRunKit

/// Shared look for the floating toolbars (Editor and Scroll Preview): one icon
/// weight/size and one card radius, so the two bars read as the same family.
enum ToolbarStyle {
    /// Slightly larger, medium-weight glyphs — crisper and more legible than the
    /// default template size, the main lift over the old toolbar.
    static let symbol = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
    /// The rounded-card corner radius of the bar itself.
    static let cornerRadius: CGFloat = 13
    /// Buttons are square, so the active-tool chip is a square and every icon has
    /// equal margins on all four sides.
    static let buttonSize: CGFloat = 30
    static let rowSpacing: CGFloat = 8
    /// Corner radius of the square selection chip — shared by the active-tool chip
    /// and the selected swatch/width chips, so "selected" is one shape everywhere.
    static let chipRadius: CGFloat = 6
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
    static let destructive = NSColor(red: 0.80, green: 0.36, blue: 0.34, alpha: 1)

    /// Faint graphite wash behind the finishing-actions tray — enough to read as a
    /// grouped "done" zone without competing with the active-tool chip.
    static var finishTray: NSColor { selection.withAlphaComponent(0.10) }

    /// A toolbar icon at the shared weight, normalised to a uniform footprint so
    /// every glyph is one size and stays inside its square chip.
    static func icon(_ name: String, _ accessibility: String) -> NSImage? {
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
final class ToolButton: NSButton {
    var isActive = false { didSet { updateAppearance() } }

    init(symbol: String, tooltip: String) {
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

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance() // re-resolve the chip's layer colour for the new light/dark
    }

    private func updateAppearance() {
        // `selection` is a dynamic colour; a CALayer colour does not auto-resolve, so
        // bake it against this view's effective appearance (also re-run on mode change).
        var chip = NSColor.clear.cgColor
        if isActive {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                chip = ToolbarStyle.selection.withAlphaComponent(0.16).cgColor
            }
        }
        layer?.backgroundColor = chip
        contentTintColor = isActive ? ToolbarStyle.selection : .secondaryLabelColor
    }
}

/// A round colour swatch — the toolbar's current-ink chip and each preset in the
/// colour popover.
final class SwatchButton: NSButton {
    var color: RGBAColor { didSet { needsDisplay = true } }
    var isSelectedSwatch = false { didSet { needsDisplay = true } }
    private let circleDiameter: CGFloat

    init(color: RGBAColor, diameter: CGFloat, target: AnyObject?, action: Selector?) {
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

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        // Selected state is a square chip, like the active-tool chip — one selection
        // shape across the whole toolbar.
        if isSelectedSwatch {
            let chip = NSBezierPath(roundedRect: bounds, xRadius: ToolbarStyle.chipRadius, yRadius: ToolbarStyle.chipRadius)
            ToolbarStyle.selection.withAlphaComponent(0.16).setFill()
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
final class WidthDotButton: NSButton {
    let width: Double
    var isSelectedWidth = false { didSet { needsDisplay = true } }

    init(width: Double, target: AnyObject?, action: Selector?) {
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

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        if isSelectedWidth {
            let chip = NSBezierPath(roundedRect: bounds, xRadius: ToolbarStyle.chipRadius, yRadius: ToolbarStyle.chipRadius)
            ToolbarStyle.selection.withAlphaComponent(0.16).setFill()
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
