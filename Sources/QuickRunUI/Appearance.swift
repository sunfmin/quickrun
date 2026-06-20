import AppKit

/// A layer-backed view whose layer colours are re-resolved on every appearance
/// change.
///
/// Separators, borders, and fills assigned straight onto `layer` as `.cgColor`
/// snapshot the colour at creation time and then ignore a light⇄dark switch — a
/// hairline built from `NSColor.separatorColor.cgColor` in one appearance keeps
/// that appearance's grey forever. Resolving the dynamic colours inside
/// `updateLayer()`, which AppKit re-runs whenever the effective appearance
/// changes, keeps them tracking the system theme.
public final class DynamicLayerView: NSView {
    public var fillColor: NSColor? { didSet { needsDisplay = true } }
    public var borderColor: NSColor? { didSet { needsDisplay = true } }
    public var borderWidth: CGFloat = 0 { didSet { needsDisplay = true } }
    public var cornerRadius: CGFloat = 0 { didSet { needsDisplay = true } }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override var wantsUpdateLayer: Bool { true }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true // re-resolve the dynamic colours for the new appearance
    }

    public override func updateLayer() {
        // `.cgColor` resolves against the current drawing appearance, which AppKit
        // sets to this view's effectiveAppearance for the duration of updateLayer.
        layer?.backgroundColor = fillColor?.cgColor
        layer?.borderColor = borderColor?.cgColor
        layer?.borderWidth = borderWidth
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = cornerRadius > 0
    }
}
