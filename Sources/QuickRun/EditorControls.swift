import AppKit
import QuickRunKit

/// A toolbar tool button that wears a seal-red pill while it is the active tool,
/// so the held tool reads at a glance instead of as a faint tint.
final class ToolButton: NSButton {
    var isActive = false { didSet { updateAppearance() } }

    init(symbol: String, tooltip: String) {
        super.init(frame: .zero)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        imagePosition = .imageOnly
        isBordered = false
        setButtonType(.momentaryChange)
        toolTip = tooltip
        wantsLayer = true
        layer?.cornerRadius = 7
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 30).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func updateAppearance() {
        layer?.backgroundColor = isActive
            ? Palette.accent.withAlphaComponent(0.16).cgColor
            : NSColor.clear.cgColor
        contentTintColor = isActive ? Palette.accent : .secondaryLabelColor
    }
}

/// A round colour swatch — the toolbar's current-ink chip and each preset in the
/// colour popover.
final class SwatchButton: NSButton {
    var color: RGBAColor { didSet { needsDisplay = true } }
    var isSelectedSwatch = false { didSet { needsDisplay = true } }

    init(color: RGBAColor, diameter: CGFloat, target: AnyObject?, action: Selector?) {
        self.color = color
        super.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        title = ""
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: diameter).isActive = true
        heightAnchor.constraint(equalToConstant: diameter).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let dot = NSBezierPath(ovalIn: bounds.insetBy(dx: 3, dy: 3))
        NSColor(color).setFill()
        dot.fill()
        // A hairline keeps white/pale inks visible against the bar.
        NSColor.separatorColor.setStroke()
        dot.lineWidth = 1
        dot.stroke()
        if isSelectedSwatch {
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
            Palette.accent.setStroke()
            ring.lineWidth = 2
            ring.stroke()
        }
    }
}

/// The colour popover: an ink palette of the colours people mark up with, laid
/// out in rows by family — brights, then deeper muted tones, then a neutral
/// ink→chalk row set off by a hairline. Seal red 朱 leads the grid; the chosen
/// ink wears the seal-red ring. A curated grid, not the system colour panel,
/// which can't show above the shield-level capture overlay.
final class ColorPaletteViewController: NSViewController {
    private let rows: [[RGBAColor]]
    private let current: RGBAColor
    private let onPick: (RGBAColor) -> Void

    /// Six swatches per row at 24pt on 10pt gaps — the rule and rows share it.
    private static let rowWidth: CGFloat = 6 * 24 + 5 * 10

    init(current: RGBAColor, onPick: @escaping (RGBAColor) -> Void) {
        self.current = current
        self.onPick = onPick
        self.rows = [
            [ // Brights — the everyday markup inks, seal red first.
              .sealRed,
              RGBAColor(red: 0.95, green: 0.45, blue: 0.18),  // orange
              RGBAColor(red: 0.96, green: 0.65, blue: 0.14),  // amber
              RGBAColor(red: 0.12, green: 0.67, blue: 0.41),  // jade
              RGBAColor(red: 0.18, green: 0.43, blue: 0.94),  // ocean
              RGBAColor(red: 0.49, green: 0.36, blue: 0.85),  // violet
            ],
            [ // Deeps — muted earth and jewel tones.
              RGBAColor(red: 0.62, green: 0.12, blue: 0.18),  // crimson
              RGBAColor(red: 0.55, green: 0.33, blue: 0.16),  // sienna
              RGBAColor(red: 0.10, green: 0.45, blue: 0.45),  // teal
              RGBAColor(red: 0.12, green: 0.22, blue: 0.45),  // navy
              RGBAColor(red: 0.40, green: 0.16, blue: 0.40),  // plum
              RGBAColor(red: 0.40, green: 0.45, blue: 0.16),  // olive
            ],
            [ // Neutrals — ink to chalk.
              RGBAColor(red: 0.11, green: 0.11, blue: 0.12),  // ink
              RGBAColor(red: 0.30, green: 0.31, blue: 0.34),  // graphite
              RGBAColor(red: 0.48, green: 0.51, blue: 0.55),  // slate
              RGBAColor(red: 0.65, green: 0.67, blue: 0.70),  // gray
              RGBAColor(red: 0.82, green: 0.84, blue: 0.86),  // silver
              RGBAColor(red: 1, green: 1, blue: 1),           // chalk
            ],
        ]
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let bright = makeRow(rows[0])
        let deep = makeRow(rows[1])
        let neutral = makeRow(rows[2])

        let rule = NSBox()
        rule.boxType = .separator
        rule.translatesAutoresizingMaskIntoConstraints = false
        rule.widthAnchor.constraint(equalToConstant: Self.rowWidth).isActive = true

        let stack = NSStackView(views: [bright, deep, rule, neutral])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSVisualEffectView()
        container.material = .menu
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.layer?.masksToBounds = true
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        view = container
    }

    private func makeRow(_ colors: [RGBAColor]) -> NSStackView {
        let swatches = colors.map { color -> SwatchButton in
            let swatch = SwatchButton(color: color, diameter: 24, target: self, action: #selector(pick(_:)))
            swatch.isSelectedSwatch = color == current
            return swatch
        }
        let row = NSStackView(views: swatches)
        row.orientation = .horizontal
        row.spacing = 10
        return row
    }

    @objc private func pick(_ sender: SwatchButton) {
        onPick(sender.color)
    }
}
