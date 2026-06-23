import AppKit
import WebKit
import QuickRunKit
import QuickRunUI

/// The Panel: an editable Query field and a Source tab bar above a stack of
/// `WKWebView`s (one per Source) that perform top-level navigation — not HTML
/// iframes, so X-Frame-Options / CSP frame-ancestors restrictions don't apply.
///
/// Tab selection and lazy loading are driven by a `PanelViewModel`: only the
/// active tab loads; switching loads an unloaded/stale tab; submitting reloads
/// the active tab and stales the rest.
///
/// Spotlight-style lifecycle: centered, floating, activates for key input,
/// dismisses on Esc or click-away, and restores focus to the prior app.
final class PanelController: NSObject, NSWindowDelegate, WKNavigationDelegate {
    private let panel: NSPanel
    let queryField: NSTextField
    private let settingsButton: NSButton
    let tabBar: SourceTabBar
    private let webContainer: NSView

    /// Called when the masthead's gear is clicked — the Panel's only in-window
    /// route to Settings, since the title bar (and any ⌘, menu) is hidden.
    var onOpenSettings: (() -> Void)?

    private var viewModel: PanelViewModel?
    private var webViews: [WKWebView] = []

    private weak var previousApp: NSRunningApplication?
    private var escMonitor: Any?
    private var isDismissing = false

    /// When dismissing into Settings, skip restoring focus to the prior app so
    /// the Settings window stays frontmost.
    private var suppressFocusRestore = false

    /// Appended to each web view's User-Agent so it contains the "Safari" token.
    /// 必应词典 sniffs the UA: browsers it recognises as Safari get an HTML5
    /// pronunciation player, everything else gets a dead Flash <object>. WKWebView's
    /// default UA lacks this token, so the speaker was silent. Presenting as Safari
    /// makes bing (and other UA-gated pages) serve the modern, working player.
    private static let safariUserAgentSuffix = "Version/17.4.1 Safari/605.1.15"

    /// `UserDefaults` key (under `NSWindow Frame <name>`) where AppKit autosaves
    /// the Panel's frame — its size and position survive across launches.
    private static let frameAutosaveName = "QuickRunPanel"

    /// True once the Panel has a frame to honour (a restored autosave, or a
    /// first-run centering), so `present` stops re-centering after that.
    private var hasPlacedPanel = false

    override init() {
        let frame = NSRect(x: 0, y: 0, width: 820, height: 620)
        panel = NSPanel(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // Build the masthead once, shared with the offscreen snapshot.
        let chrome = PanelChrome.build(frame: frame)
        queryField = chrome.queryField
        settingsButton = chrome.settingsButton
        tabBar = chrome.tabBar
        webContainer = chrome.contentRegion
        super.init()

        panel.title = "QuickRun"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.delegate = self

        // A summoned HUD has no chrome: hide the title bar and traffic lights so
        // the Query becomes the topmost element. Esc and click-away already
        // dismiss, so the close button is redundant; drag by the bar instead.
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }

        // Wire the chrome's controls to this controller (the snapshot leaves them inert).
        settingsButton.target = self
        settingsButton.action = #selector(openSettings)
        queryField.target = self
        queryField.action = #selector(submit)
        tabBar.onSelect = { [weak self] index in self?.tabSelected(index) }

        panel.contentView = chrome.content

        // Restore the last size/position, then let AppKit autosave further
        // resizes and moves. A restored frame counts as placed, so present()
        // won't recenter over the user's choice.
        hasPlacedPanel = panel.setFrameUsingName(Self.frameAutosaveName)
        panel.setFrameAutosaveName(Self.frameAutosaveName)

        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible, event.keyCode == 53 else { return event }
            self.dismiss()
            return nil
        }
    }

    deinit {
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
    }

    /// Show the Panel for `sources`, seeding the Query from `selection`. A
    /// non-empty Selection loads the first tab; an empty one leaves the focused
    /// field blank with no navigation.
    func present(selection: String, sources: [Source]) {
        setupIfNeeded(for: sources)
        suppressFocusRestore = false
        previousApp = NSWorkspace.shared.frontmostApplication

        let request = viewModel?.open(selection: selection)
        projectChrome()
        showActiveWebView()
        if let request { execute(request) }

        if !hasPlacedPanel {
            panel.center()
            hasPlacedPanel = true
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(queryField)
        queryField.selectText(nil)

        // Tint the caret seal-red to match the active-Source rule.
        if let editor = panel.fieldEditor(true, for: queryField) as? NSTextView {
            editor.insertionPointColor = Palette.accent
        }
    }

    func dismiss() {
        guard !isDismissing, panel.isVisible else { return }
        isDismissing = true
        panel.orderOut(nil)
        if !suppressFocusRestore { previousApp?.activate() }
        suppressFocusRestore = false
        isDismissing = false
    }

    /// Whether the Panel is currently on screen.
    var isVisible: Bool { panel.isVisible }

    /// The Panel's window, so a capture overlay can host it above the frozen
    /// screen (which sits at the shield level, above ordinary floating windows).
    var hostWindow: NSWindow { panel }

    // MARK: - Snapshot seam

    /// Seed the real masthead for `sources` and `selection` — building the actual
    /// `PanelViewModel` and projecting it onto the chrome — without creating the
    /// offscreen-incapable `WKWebView`s or showing the window. Drives the live code
    /// path for `SnapshotTests`; the caller drops a static result pane into
    /// `snapshotContentRegion` to stand in for the loaded page.
    func configureForSnapshot(sources: [Source], selection: String) {
        makeViewModelAndTabs(for: sources)
        _ = viewModel?.open(selection: selection)
        projectChrome()
    }

    /// The masthead content view (the `NSVisualEffectView` body), for offscreen
    /// rendering after `configureForSnapshot`.
    var snapshotContentView: NSView? { panel.contentView }

    /// The results region, where the live Panel hosts its `WKWebView`s — a snapshot
    /// fills it with a static stand-in instead.
    var snapshotContentRegion: NSView { webContainer }

    /// Look up whatever text is selected inside the active web view (used when the
    /// hotkey fires while QuickRun is already frontmost). Reads the selection via
    /// JavaScript — no synthetic copy — so it can't beep or pick up the wrong text.
    /// With nothing selected it just refocuses the Query field.
    func lookUpSelectionInActiveWebView() {
        let active = viewModel?.activeIndex ?? 0
        guard webViews.indices.contains(active) else { return }
        webViews[active].evaluateJavaScript("window.getSelection().toString()") { [weak self] result, _ in
            guard let self else { return }
            let text = (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else {
                self.panel.makeFirstResponder(self.queryField)
                self.queryField.selectText(nil)
                return
            }
            self.run(query: text)
        }
    }

    // MARK: - Setup

    /// Build the tab bar and one WKWebView per Source. Rebuilt only when the set
    /// of Sources changes (the dynamic Source store arrives in a later slice).
    private func setupIfNeeded(for sources: [Source]) {
        if let vm = viewModel, vm.sources == sources { return }

        makeViewModelAndTabs(for: sources)

        webViews.forEach { $0.removeFromSuperview() }
        webViews = sources.map { _ in
            let config = WKWebViewConfiguration()
            // Present as Safari so UA-sniffing pages (e.g. 必应词典's
            // pronunciation) serve their HTML5 player instead of a dead Flash one.
            config.applicationNameForUserAgent = Self.safariUserAgentSuffix
            // Allow audio that plays after an async step (no direct user gesture).
            config.mediaTypesRequiringUserActionForPlayback = []
            let webView = WKWebView(frame: webContainer.bounds, configuration: config)
            webView.autoresizingMask = [.width, .height]
            webView.navigationDelegate = self
            webView.isHidden = true
            webContainer.addSubview(webView)
            return webView
        }
    }

    /// The data → chrome half of setup: the view model and the Source tab bar.
    /// Split out from web-view creation so a snapshot can drive the real chrome
    /// without instantiating `WKWebView`s (which can't render offscreen).
    private func makeViewModelAndTabs(for sources: [Source]) {
        viewModel = PanelViewModel(sources: sources)
        tabBar.configure(sources.map(\.name))
    }

    /// Project the view model's Query and active Source onto the masthead — the
    /// shared "model owns it, chrome shows it" step run by both `present` and the
    /// offscreen snapshot.
    private func projectChrome() {
        renderQuery()
        tabBar.select(viewModel?.activeIndex ?? 0, animated: false)
    }

    // MARK: - Actions

    @objc private func submit() {
        run(query: queryField.stringValue)
    }

    /// Run a Query through the view model — the single place a Query is committed
    /// to the model — then project the model's Query back onto the field so the
    /// two never drift.
    private func run(query: String) {
        if let request = viewModel?.submit(query: query) { execute(request) }
        renderQuery()
    }

    /// The Query field is a projection of `PanelViewModel.query`: the model owns
    /// the Query, the field shows it. Called after every path that changes the
    /// model's Query — open, tab switch, submit.
    private func renderQuery() {
        guard let viewModel else { return }
        queryField.stringValue = viewModel.query
    }

    @objc private func openSettings() {
        // Settings is about to become key, which resigns the Panel and dismisses
        // it — but focus should land on Settings, not bounce to the prior app.
        suppressFocusRestore = true
        onOpenSettings?()
    }

    private func tabSelected(_ index: Int) {
        showActiveWebView(index: index)
        if let request = viewModel?.switchTo(index) { execute(request) }
        renderQuery()
    }

    private func execute(_ request: LoadRequest) {
        guard webViews.indices.contains(request.index) else { return }
        webViews[request.index].load(URLRequest(url: request.url))
    }

    private func showActiveWebView(index: Int? = nil) {
        let active = index ?? viewModel?.activeIndex ?? 0
        for (i, webView) in webViews.enumerated() {
            webView.isHidden = i != active
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let index = webViews.firstIndex(of: webView) {
            viewModel?.loadDidFinish(index)
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        dismiss()
    }
}
