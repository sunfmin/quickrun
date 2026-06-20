import AppKit

/// The Panel's masthead chrome: the translucent instrument bar — a lens, the serif
/// Query field, a gear, the Source tab bar, and a single closing hairline — above a
/// content region where results render.
///
/// Built here so the live Panel (`PanelController`) and the offscreen snapshot
/// (`PanelSnapshot`) lay out the *identical* chrome from one source — no
/// hand-mirrored copy to keep in sync. Only the content region differs: the live
/// Panel fills it with `WKWebView`s, the snapshot drops in a static result pane.
public struct PanelChrome {
    /// The material-backed panel body; becomes the window's `contentView`.
    public let content: NSVisualEffectView
    public let lens: NSImageView
    public let queryField: NSTextField
    public let settingsButton: NSButton
    public let tabBar: SourceTabBar
    /// Where results live — WKWebViews live, a static pane in the snapshot.
    public let contentRegion: NSView

    /// Height of the instrument bar (Query row + Source row) above the content
    /// region. One frosted header zone closed by a single hairline — the active
    /// Source's seal-red underline does the structuring inside it, so no rule
    /// divides Query from Sources.
    public static let topInset: CGFloat = 96

    public static func build(frame: NSRect) -> PanelChrome {
        // Translucent material for the instrument bar — fitting for a panel that
        // floats over whatever you were reading. The opaque content covers the
        // rest, so the vibrancy only shows through the top bar.
        let content = NSVisualEffectView(frame: frame)
        content.material = .titlebar
        content.state = .active
        content.blendingMode = .behindWindow
        content.autoresizingMask = [.width, .height]

        // Query, lens, and gear share a baseline centred at `rowCenter`; the serif
        // Query is the hero, the lens hangs into the left margin as its instrument.
        let rowCenter = frame.height - 33

        let lens = NSImageView()
        let lensConfig = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        lens.image = NSImage(systemSymbolName: "text.magnifyingglass", accessibilityDescription: "Look up")?
            .withSymbolConfiguration(lensConfig)
        lens.contentTintColor = .secondaryLabelColor
        lens.frame = NSRect(x: 18, y: rowCenter - 11, width: 22, height: 22)
        lens.autoresizingMask = [.minYMargin]
        content.addSubview(lens)

        let settingsButton = NSButton()
        let gearConfig = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")?
            .withSymbolConfiguration(gearConfig)
        settingsButton.isBordered = false
        settingsButton.setButtonType(.momentaryChange)
        settingsButton.contentTintColor = .secondaryLabelColor
        settingsButton.imagePosition = .imageOnly
        settingsButton.toolTip = "Settings"
        settingsButton.frame = NSRect(x: frame.width - 18 - 22, y: rowCenter - 11, width: 22, height: 22)
        settingsButton.autoresizingMask = [.minXMargin, .minYMargin]
        content.addSubview(settingsButton)

        let queryField = NSTextField()
        queryField.frame = NSRect(x: 48, y: rowCenter - 15, width: frame.width - 48 - 52, height: 30)
        queryField.autoresizingMask = [.width, .minYMargin]
        queryField.placeholderString = "Look up…"
        queryField.font = .quickRunSerif(ofSize: 22, weight: .medium)
        queryField.textColor = .labelColor
        queryField.isBordered = false
        queryField.drawsBackground = false
        queryField.focusRingType = .none
        queryField.cell?.usesSingleLineMode = true
        queryField.cell?.isScrollable = true
        content.addSubview(queryField)

        // The Source row sits a comfortable gap below the Query; its seal-red
        // underline rides just above the closing rule, so the active Source points
        // into its result.
        let tabBar = SourceTabBar(frame: NSRect(x: 48, y: frame.height - 92, width: frame.width - 48 - 18, height: 30))
        tabBar.autoresizingMask = [.width, .minYMargin]
        content.addSubview(tabBar)

        content.addSubview(hairline(width: frame.width, y: frame.height - topInset))

        let contentRegion = NSView(frame: NSRect(x: 0, y: 0, width: frame.width, height: frame.height - topInset))
        contentRegion.autoresizingMask = [.width, .height]
        content.addSubview(contentRegion)

        return PanelChrome(
            content: content,
            lens: lens,
            queryField: queryField,
            settingsButton: settingsButton,
            tabBar: tabBar,
            contentRegion: contentRegion
        )
    }

    /// A full-bleed 1pt rule that tracks light/dark, pinned by its top edge.
    private static func hairline(width: CGFloat, y: CGFloat) -> NSView {
        let rule = DynamicLayerView(frame: NSRect(x: 0, y: y, width: width, height: 1))
        rule.fillColor = .separatorColor
        rule.autoresizingMask = [.width, .minYMargin]
        return rule
    }
}
