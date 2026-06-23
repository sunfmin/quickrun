import AppKit
import QuickRunUI

/// Shared offscreen-render helpers for the snapshot tests: rasterize a view to a
/// PNG, and the few backdrops that stand in for the materials AppKit can't render
/// offscreen (the window background, the Panel's translucent titlebar, the
/// toolbar's blurred card). The real UI is driven by the live controllers; these
/// only supply the surface behind it.
enum SnapshotImage {
    static func write(_ view: NSView, to url: URL) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        if #available(macOS 11.0, *) {
            view.appearance?.performAsCurrentDrawingAppearance {
                view.cacheDisplay(in: view.bounds, to: rep)
            }
        } else {
            view.cacheDisplay(in: view.bounds, to: rep)
        }
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
}

/// A host painting `windowBackgroundColor` behind `content`, tracking the
/// appearance — a plain `layer.backgroundColor` would freeze the light value set
/// before the appearance applied. For the Settings window content.
func windowBackgroundHost(_ content: NSView, appearance: NSAppearance) -> NSView {
    let host = DynamicLayerView(frame: content.bounds)
    host.fillColor = .windowBackgroundColor
    host.appearance = appearance
    content.appearance = appearance
    host.addSubview(content)
    host.layoutSubtreeIfNeeded()
    return host
}

/// A solid backdrop approximating the Panel's translucent `.titlebar` material,
/// which renders clear offscreen. For the Panel masthead content.
func titlebarMaterialHost(_ content: NSView, appearance: NSAppearance) -> NSView {
    let isDark = appearance.name == .darkAqua
    let host = NSView(frame: content.bounds)
    host.wantsLayer = true
    host.layer?.backgroundColor = (isDark ? NSColor(white: 0.17, alpha: 1) : NSColor(white: 0.96, alpha: 1)).cgColor
    host.appearance = appearance
    content.appearance = appearance
    host.addSubview(content)
    host.layoutSubtreeIfNeeded()
    return host
}

/// Wrap `content` in a material-approximating rounded card with a shadow, over a
/// neutral backdrop, sized to fit. For the floating toolbar bits, whose
/// `NSVisualEffectView` blur can't render offscreen.
func toolbarCard(_ content: NSView, appearance: NSAppearance) -> NSView {
    content.translatesAutoresizingMaskIntoConstraints = false
    let fit = content.fittingSize

    let isDark = appearance.name == .darkAqua
    let card = NSView(frame: NSRect(origin: .zero, size: fit))
    card.wantsLayer = true
    card.layer?.backgroundColor = (isDark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.98, alpha: 1)).cgColor
    card.layer?.cornerRadius = ToolbarStyle.cornerRadius
    card.layer?.borderWidth = 0.5
    card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.4).cgColor
    card.addSubview(content)
    NSLayoutConstraint.activate([
        content.leadingAnchor.constraint(equalTo: card.leadingAnchor),
        content.trailingAnchor.constraint(equalTo: card.trailingAnchor),
        content.topAnchor.constraint(equalTo: card.topAnchor),
        content.bottomAnchor.constraint(equalTo: card.bottomAnchor),
    ])

    let pad: CGFloat = 36
    let host = NSView(frame: NSRect(x: 0, y: 0, width: fit.width + pad * 2, height: fit.height + pad * 2))
    host.wantsLayer = true
    host.layer?.backgroundColor = (isDark ? NSColor(white: 0.10, alpha: 1) : NSColor(white: 0.90, alpha: 1)).cgColor
    host.appearance = appearance
    card.appearance = appearance
    card.setFrameOrigin(NSPoint(x: pad, y: pad))
    card.shadow = {
        let s = NSShadow()
        s.shadowColor = NSColor.black.withAlphaComponent(isDark ? 0.6 : 0.25)
        s.shadowBlurRadius = 16
        s.shadowOffset = NSSize(width: 0, height: -5)
        return s
    }()
    host.addSubview(card)
    host.layoutSubtreeIfNeeded()
    return host
}
