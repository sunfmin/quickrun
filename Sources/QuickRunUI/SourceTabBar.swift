import AppKit

/// The Panel's chrome palette. One saturated accent — a Chinese seal red (朱)
/// that rhymes with 有道's red brand mark — used only for the active Source's
/// underline and the Query caret. Everything else is system-semantic so it
/// adapts to light/dark and the translucent material behind it.
public enum Palette {
    public static let accent = NSColor(red: 0.84, green: 0.27, blue: 0.24, alpha: 1)
}

extension NSFont {
    /// Apple's New York serif — the family face shared across QuickRun's windows:
    /// the Panel's Query headword and the Settings section headers. Dictionaries
    /// set headwords in serif, so it ties the chrome to the subject.
    public static func quickRunSerif(ofSize size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let system = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = system.fontDescriptor.withDesign(.serif) else { return system }
        return NSFont(descriptor: descriptor, size: size) ?? system
    }
}

/// The Source switcher: a left-aligned row of text labels with a seal-red rule
/// that slides under the active Source. Replaces NSSegmentedControl so the
/// active Source reads like the masthead of a dictionary entry — ink label over
/// a red rule — rather than a system-blue toolbar segment.
public final class SourceTabBar: NSView {
    /// Called with the tapped Source index when the user picks a tab.
    public var onSelect: ((Int) -> Void)?

    private var buttons: [NSButton] = []
    private let underline = NSView()

    private static let labelFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    private static let gap: CGFloat = 22
    private static let underlineHeight: CGFloat = 2

    public private(set) var selectedIndex = 0

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        underline.wantsLayer = true
        underline.layer?.backgroundColor = Palette.accent.cgColor
        underline.layer?.cornerRadius = Self.underlineHeight / 2
        addSubview(underline)
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Rebuild the row for `names`, selecting the first Source.
    public func configure(_ names: [String]) {
        buttons.forEach { $0.removeFromSuperview() }
        buttons = names.enumerated().map { index, name in
            let button = NSButton(title: name, target: self, action: #selector(tap(_:)))
            button.isBordered = false
            button.setButtonType(.momentaryChange)
            button.font = Self.labelFont
            button.tag = index
            addSubview(button)
            return button
        }
        selectedIndex = 0
        layoutButtons()
        applySelection(animated: false)
    }

    /// Move the selection (and slide the rule) without firing `onSelect`.
    public func select(_ index: Int, animated: Bool = true) {
        guard buttons.indices.contains(index) else { return }
        selectedIndex = index
        applySelection(animated: animated)
    }

    @objc private func tap(_ sender: NSButton) {
        select(sender.tag)
        onSelect?(sender.tag)
    }

    public override func layout() {
        super.layout()
        layoutButtons()
        applySelection(animated: false)
    }

    private func layoutButtons() {
        var x: CGFloat = 0
        let midY = bounds.midY
        for button in buttons {
            button.sizeToFit()
            let height = button.frame.height
            button.frame = NSRect(x: x, y: (midY - height / 2).rounded(), width: button.frame.width, height: height)
            x += button.frame.width + Self.gap
        }
    }

    private func applySelection(animated: Bool) {
        for (i, button) in buttons.enumerated() {
            button.attributedTitle = title(button.title, active: i == selectedIndex)
        }
        guard buttons.indices.contains(selectedIndex) else {
            underline.isHidden = true
            return
        }
        underline.isHidden = false
        let target = buttons[selectedIndex]
        let frame = NSRect(x: target.frame.minX, y: 0, width: target.frame.width, height: Self.underlineHeight)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if animated && !reduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                underline.animator().frame = frame
            }
        } else {
            underline.frame = frame
        }
    }

    private func title(_ text: String, active: Bool) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: Self.labelFont,
            .foregroundColor: active ? NSColor.labelColor : NSColor.secondaryLabelColor,
        ])
    }
}
