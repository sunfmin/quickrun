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

/// A Recognized word, set as a serif headword that highlights on hover so the
/// list reads like a column of dictionary entries waiting to be looked up.
final class WordRowButton: NSButton {
    private var hovering = false { didSet { updateBackground() } }

    init(word: String, target: AnyObject, action: Selector) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        setButtonType(.momentaryChange)
        wantsLayer = true
        layer?.cornerRadius = 6
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 30).isActive = true

        let indented = NSMutableParagraphStyle()
        indented.firstLineHeadIndent = 10
        indented.alignment = .left
        attributedTitle = NSAttributedString(string: word, attributes: [
            .font: NSFont.quickRunSerif(ofSize: 16, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: indented,
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    private func updateBackground() {
        layer?.backgroundColor = hovering ? Palette.accent.withAlphaComponent(0.10).cgColor : NSColor.clear.cgColor
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

/// The colour popover: the inks people actually mark up with, one click away,
/// plus a well for anything else.
final class ColorPaletteViewController: NSViewController {
    private let presets: [RGBAColor]
    private let current: RGBAColor
    private let onPick: (RGBAColor) -> Void
    private let well = NSColorWell()

    init(current: RGBAColor, onPick: @escaping (RGBAColor) -> Void) {
        self.current = current
        self.onPick = onPick
        self.presets = [
            .sealRed,
            RGBAColor(red: 0.11, green: 0.11, blue: 0.12),  // ink
            RGBAColor(red: 1, green: 1, blue: 1),           // chalk
            RGBAColor(red: 0.18, green: 0.43, blue: 0.94),  // ocean
            RGBAColor(red: 0.12, green: 0.67, blue: 0.41),  // jade
            RGBAColor(red: 0.96, green: 0.65, blue: 0.14),  // amber
        ]
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let swatches = presets.map { preset -> SwatchButton in
            let swatch = SwatchButton(color: preset, diameter: 26, target: self, action: #selector(pickPreset(_:)))
            swatch.isSelectedSwatch = preset == current
            return swatch
        }
        let row = NSStackView(views: swatches)
        row.orientation = .horizontal
        row.spacing = 8

        let customLabel = NSTextField(labelWithString: "Custom")
        customLabel.font = .systemFont(ofSize: 11)
        customLabel.textColor = .secondaryLabelColor
        well.color = NSColor(current)
        well.target = self
        well.action = #selector(pickCustom(_:))
        well.translatesAutoresizingMaskIntoConstraints = false
        well.widthAnchor.constraint(equalToConstant: 44).isActive = true
        well.heightAnchor.constraint(equalToConstant: 22).isActive = true
        if #available(macOS 13.0, *) { well.colorWellStyle = .minimal }
        let customRow = NSStackView(views: [customLabel, well])
        customRow.orientation = .horizontal
        customRow.spacing = 8

        let stack = NSStackView(views: [row, customRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        view = container
    }

    @objc private func pickPreset(_ sender: SwatchButton) {
        onPick(sender.color)
    }

    @objc private func pickCustom(_ sender: NSColorWell) {
        onPick(sender.color.rgba)
    }
}
