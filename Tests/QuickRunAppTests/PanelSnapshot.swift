import AppKit
import QuickRunKit
import QuickRunUI
@testable import QuickRun

/// Renders the Panel — QuickRun's look-up *results window* — to PNGs offscreen.
/// Driven by `PanelSnapshotTests`.
///
/// It drives the *real* `PanelController`: `configureForSnapshot` builds the actual
/// `PanelViewModel` for the example Sources, opens the Selection, and projects the
/// Query and active Source onto the masthead exactly as `present` does live — no
/// hand-posed chrome. The one thing mocked is the lowest, un-renderable seam: a
/// `WKWebView` page can't render offscreen and would need the network, so a static
/// dictionary-entry result stands in for the loaded page. The translucent titlebar
/// material can't render offscreen either, so the masthead sits on a solid backdrop.
enum PanelSnapshot {
    private static let exampleQuery = "ephemeral"
    static let exampleSources: [Source] = [
        Source(name: "有道词典", urlTemplate: "https://dict.youdao.com/result?word={q}&lang=en"),
        Source(name: "Google", urlTemplate: "https://www.google.com/search?q={q}"),
    ]

    static func render(toDirectory directory: String) {
        let dir = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for (suffix, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let appearance = NSAppearance(named: appearanceName)!
            let (host, _) = pose(appearance: appearance)
            SnapshotImage.write(host, to: dir.appendingPathComponent("panel-look-up-\(suffix).png"))
        }
    }

    /// Drive the real controller for the example look-up, drop a static result pane
    /// into the content region (the mocked page), and host the masthead on a
    /// material-approximating backdrop. Returns the host and the controller (for
    /// content assertions on the real chrome).
    static func pose(appearance: NSAppearance) -> (host: NSView, controller: PanelController) {
        let controller = PanelController()
        controller.configureForSnapshot(sources: exampleSources, selection: exampleQuery)

        let region = controller.snapshotContentRegion
        let result = resultPane(query: exampleQuery, isDark: appearance.name == .darkAqua)
        result.frame = region.bounds
        result.autoresizingMask = [.width, .height]
        region.addSubview(result)

        let content = controller.snapshotContentView!
        content.removeFromSuperview()
        let host = titlebarMaterialHost(content, appearance: appearance)
        controller.tabBar.layoutSubtreeIfNeeded()
        return (host, controller)
    }

    // MARK: - Result pane (the mocked page — stands in for the un-renderable WKWebView)

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
}
