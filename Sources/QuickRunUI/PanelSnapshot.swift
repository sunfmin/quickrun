import AppKit

/// Renders the Panel — QuickRun's look-up *results window* — to PNGs offscreen so
/// its look can be reviewed (and fed to a design pass) without launching the
/// capture flow or hitting the network. Driven by `PanelSnapshotTests`.
///
/// It builds the real masthead via `PanelChrome` (the same lens, serif Query field,
/// gear, hairline and `SourceTabBar` the live Panel ships), so the visual tokens
/// under review are the real ones. The data seam is mocked at the *lowest* layer: a
/// `WKWebView` page can't render offscreen and would need the network, so the
/// content region gets a static dictionary-entry result that stands in for the
/// loaded page. `NSVisualEffectView` blur can't render offscreen either, so the bar
/// sits on a solid backdrop that approximates the `.titlebar` material — a faithful
/// stand-in for layout and colour review.
public enum PanelSnapshot {
    private static let panelSize = NSSize(width: 820, height: 620)

    /// Posed example: a headword being looked up, across the shipped default Sources.
    private static let exampleQuery = "ephemeral"
    private static let exampleSources = ["有道词典", "Google"]

    /// Render `panel-look-up-light.png` and `panel-look-up-dark.png` into `directory`.
    public static func render(toDirectory directory: String) {
        let dir = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for (suffix, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let appearance = NSAppearance(named: appearanceName)!
            let window = poseWindow(appearance: appearance)
            write(window, to: dir.appendingPathComponent("panel-look-up-\(suffix).png"))
        }
    }

    // MARK: - Pose

    /// Build the real chrome, seed it with the example look-up, drop a static result
    /// pane into the content region, and sit it all on a material-approximating host.
    private static func poseWindow(appearance: NSAppearance) -> NSView {
        let frame = NSRect(origin: .zero, size: panelSize)
        let chrome = PanelChrome.build(frame: frame)
        chrome.queryField.stringValue = exampleQuery
        chrome.tabBar.configure(exampleSources)
        chrome.tabBar.select(0, animated: false)

        let result = resultPane(query: exampleQuery, isDark: appearance.name == .darkAqua)
        result.frame = chrome.contentRegion.bounds
        result.autoresizingMask = [.width, .height]
        chrome.contentRegion.addSubview(result)

        // Offscreen, the NSVisualEffectView renders clear; back it with a solid
        // colour that reads like the translucent titlebar material.
        let host = NSView(frame: frame)
        host.wantsLayer = true
        host.layer?.backgroundColor = (appearance.name == .darkAqua
            ? NSColor(white: 0.17, alpha: 1)
            : NSColor(white: 0.96, alpha: 1)).cgColor
        host.appearance = appearance
        chrome.content.appearance = appearance
        host.addSubview(chrome.content)
        host.layoutSubtreeIfNeeded()
        chrome.tabBar.layoutSubtreeIfNeeded()
        return host
    }

    // MARK: - Result pane (the mocked data seam — stands in for the loaded page)

    /// A static dictionary entry for `query`, the kind of result the active Source
    /// would load. Plain AppKit on an opaque page so it reads as the result area.
    private static func resultPane(query: String, isDark: Bool) -> NSView {
        let page = NSView()
        page.wantsLayer = true
        page.layer?.backgroundColor = (isDark ? NSColor(white: 0.13, alpha: 1) : .white).cgColor

        let headword = label(query, font: .quickRunSerif(ofSize: 34, weight: .semibold), color: .labelColor)
        let phonetic = label("/ɪˈfem(ə)rəl/", font: .quickRunSerif(ofSize: 17, weight: .regular), color: .secondaryLabelColor)

        let entries = NSStackView(views: [
            sense("adj.", "lasting for a very short time; 短暂的，转瞬即逝的"),
            sense("adj.", "（生物）只存活一天的；朝生暮死的"),
            sense("n.", "短命植物；只生存一天的事物"),
        ])
        entries.orientation = .vertical
        entries.alignment = .leading
        entries.spacing = 14

        let example = label("“the ephemeral nature of fashion” — 时尚转瞬即逝的本质",
                            font: .systemFont(ofSize: 14, weight: .regular), color: .secondaryLabelColor)

        let column = NSStackView(views: [headword, phonetic, spacer(8), entries, spacer(12), example])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 6
        column.translatesAutoresizingMaskIntoConstraints = false
        page.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 48),
            column.trailingAnchor.constraint(lessThanOrEqualTo: page.trailingAnchor, constant: -48),
            column.topAnchor.constraint(equalTo: page.topAnchor, constant: 40),
        ])
        return page
    }

    /// One sense: a seal-red part-of-speech chip and its gloss.
    private static func sense(_ pos: String, _ gloss: String) -> NSView {
        let chip = label(pos, font: .systemFont(ofSize: 13, weight: .medium), color: Palette.accent)
        let text = label(gloss, font: .systemFont(ofSize: 16, weight: .regular), color: .labelColor)
        let row = NSStackView(views: [chip, text])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 10
        return row
    }

    private static func label(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = font
        field.textColor = color
        return field
    }

    private static func spacer(_ height: CGFloat) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }

    // MARK: - Render

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
