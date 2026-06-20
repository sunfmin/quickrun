import AppKit
import QuickRunKit

/// Dev-only: renders the floating toolbars to PNGs offscreen so their look can be
/// reviewed (and fed to a design pass) without launching the capture flow. Invoked
/// by `QuickRun --snapshot-toolbar <dir>` (see main.swift).
///
/// It builds the bars from the *same* `ToolbarStyle`, button classes, and
/// `StylePresets` the live toolbars use, so the visual tokens under review — icon
/// size/weight, colours, radii, spacing, the active-tool chip — are the real ones.
/// `NSVisualEffectView` blur can't render offscreen, so the bar is shown on a card
/// that approximates the `.menu` material; that's a faithful stand-in for layout
/// and colour review. The composition here mirrors `CaptureOverlayController`.
enum ToolbarSnapshot {
    static func render(toDirectory directory: String) {
        let dir = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for (suffix, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let appearance = NSAppearance(named: appearanceName)!
            write(card(content: editorToolbarColumn(), appearance: appearance),
                  to: dir.appendingPathComponent("toolbar-editor-\(suffix).png"))
            write(card(content: scrollPillRow(), appearance: appearance),
                  to: dir.appendingPathComponent("toolbar-scroll-\(suffix).png"))
        }
        FileHandle.standardError.write("Rendered toolbar snapshots to \(dir.path)\n".data(using: .utf8)!)
    }

    // MARK: - Editor toolbar (mirrors CaptureOverlayController.buildToolbar)

    private static func editorToolbarColumn() -> NSView {
        let tools: [(String, String, Bool)] = [
            ("cursorarrow", "Select", false),
            ("rectangle", "Rectangle", false),
            ("circle", "Ellipse", false),
            ("face.smiling", "Emoji", false),
            ("arrow.up.right", "Arrow", false),
            ("pencil.tip", "Pen", true), // show the active-tool chip
            ("highlighter", "Highlighter", false),
            ("square.grid.3x3", "Blur / redact", false),
            ("textformat", "Text", false),
        ]
        var views: [NSView] = tools.map { symbol, tooltip, active in
            let button = ToolButton(symbol: symbol, tooltip: tooltip)
            button.isActive = active
            return button
        }
        let scrollCapture = actionButton("arrow.up.and.down", tint: .secondaryLabelColor)
        let editDivider = divider()
        let delete = actionButton("trash", tint: .secondaryLabelColor)
        let finishTray = Self.finishTray([
            actionButton("doc.plaintext", tint: .secondaryLabelColor),
            actionButton("doc.on.clipboard", tint: .secondaryLabelColor),
            actionButton("square.and.arrow.down", tint: .secondaryLabelColor),
        ])
        views += [
            scrollCapture,
            editDivider,
            actionButton("arrow.uturn.backward", tint: .secondaryLabelColor),
            actionButton("arrow.uturn.forward", tint: .secondaryLabelColor),
            delete,
            finishTray,
            actionButton("xmark", tint: ToolbarStyle.destructive),
        ]

        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.spacing = ToolbarStyle.rowSpacing
        let groupGap: CGFloat = 14
        row.setCustomSpacing(groupGap, after: scrollCapture)
        row.setCustomSpacing(groupGap, after: editDivider)
        row.setCustomSpacing(18, after: delete)
        row.setCustomSpacing(10, after: finishTray)

        let strip = styleStrip()
        let column = NSStackView(views: [row, strip])
        column.orientation = .vertical
        column.alignment = .centerX
        column.spacing = 10
        column.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        strip.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true
        return column
    }

    /// Faint rounded tray grouping the finishing actions (mirrors `makeFinishTray`).
    private static func finishTray(_ buttons: [NSView]) -> NSView {
        let stack = NSStackView(views: buttons)
        stack.orientation = .horizontal
        stack.spacing = ToolbarStyle.rowSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        let tray = DynamicLayerView()
        tray.fillColor = ToolbarStyle.finishTray
        tray.cornerRadius = 9
        tray.translatesAutoresizingMaskIntoConstraints = false
        tray.addSubview(stack)
        let pad: CGFloat = 6
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: tray.leadingAnchor, constant: pad),
            stack.trailingAnchor.constraint(equalTo: tray.trailingAnchor, constant: -pad),
            stack.topAnchor.constraint(equalTo: tray.topAnchor),
            stack.bottomAnchor.constraint(equalTo: tray.bottomAnchor),
        ])
        return tray
    }

    private static func styleStrip() -> NSStackView {
        let widths = StylePresets.widths.enumerated().map { index, width -> WidthDotButton in
            let dot = WidthDotButton(width: width, target: nil, action: nil)
            dot.isSelectedWidth = index == 1
            return dot
        }
        let swatches = StylePresets.colors.enumerated().map { index, color -> SwatchButton in
            let swatch = SwatchButton(color: color, diameter: 22, target: nil, action: nil)
            swatch.isSelectedSwatch = index == 0
            return swatch
        }
        let strip = NSStackView(views: widths + swatches)
        strip.orientation = .horizontal
        strip.spacing = 8
        strip.distribution = .equalSpacing
        return strip
    }

    // MARK: - Scroll-capture pill (mirrors ScrollPreviewPane)

    private static func scrollPillRow() -> NSView {
        let save = actionButton("square.and.arrow.down", tint: .secondaryLabelColor)
        let separator = divider()
        let row = NSStackView(views: [
            actionButton("doc.on.clipboard", tint: .secondaryLabelColor),
            save,
            separator,
            actionButton("xmark", tint: .systemRed),
        ])
        row.orientation = .horizontal
        row.spacing = ToolbarStyle.rowSpacing
        row.setCustomSpacing(14, after: save)
        row.setCustomSpacing(14, after: separator)
        row.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        return row
    }

    // MARK: - Shared builders

    private static func actionButton(_ symbol: String, tint: NSColor) -> NSButton {
        let button = NSButton()
        button.image = ToolbarStyle.icon(symbol, symbol)
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.contentTintColor = tint
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: ToolbarStyle.buttonSize).isActive = true
        button.heightAnchor.constraint(equalToConstant: ToolbarStyle.buttonSize).isActive = true
        return button
    }

    private static func divider() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        line.widthAnchor.constraint(equalToConstant: 1).isActive = true
        line.heightAnchor.constraint(equalToConstant: 22).isActive = true
        return line
    }

    // MARK: - Render

    /// Wrap `content` in a material-approximating rounded card with a shadow, over a
    /// neutral backdrop, sized to fit.
    private static func card(content: NSView, appearance: NSAppearance) -> NSView {
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
        // Shadow lives on the card; the card clips its corners, so cast it via the host.
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

    private static func write(_ view: NSView, to url: URL) {
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
