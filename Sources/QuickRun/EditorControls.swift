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
        widthAnchor.constraint(equalToConstant: 26).isActive = true
        heightAnchor.constraint(equalToConstant: 26).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let diameter = min(bounds.width - 6, CGFloat(width) + 5)
        let dot = NSBezierPath(ovalIn: CGRect(x: bounds.midX - diameter / 2,
                                              y: bounds.midY - diameter / 2,
                                              width: diameter, height: diameter))
        (isSelectedWidth ? Palette.accent : NSColor.secondaryLabelColor).setFill()
        dot.fill()
        if isSelectedWidth {
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
            Palette.accent.setStroke()
            ring.lineWidth = 2
            ring.stroke()
        }
    }
}
