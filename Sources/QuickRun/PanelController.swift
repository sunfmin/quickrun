import AppKit
import WebKit
import QuickRunKit

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
    private let queryField = NSTextField()
    private let tabs = NSSegmentedControl()
    private let webContainer = NSView()

    private var viewModel: PanelViewModel?
    private var webViews: [WKWebView] = []

    private weak var previousApp: NSRunningApplication?
    private var escMonitor: Any?
    private var isDismissing = false

    private let topInset: CGFloat = 70

    override init() {
        let frame = NSRect(x: 0, y: 0, width: 820, height: 620)
        panel = NSPanel(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.title = "QuickRun"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.delegate = self

        let content = NSView(frame: frame)

        queryField.frame = NSRect(x: 8, y: frame.height - 36, width: frame.width - 16, height: 28)
        queryField.autoresizingMask = [.width, .minYMargin]
        queryField.placeholderString = "Look up…"
        queryField.font = .systemFont(ofSize: 15)
        queryField.target = self
        queryField.action = #selector(submit)
        content.addSubview(queryField)

        tabs.frame = NSRect(x: 8, y: frame.height - 66, width: frame.width - 16, height: 24)
        tabs.autoresizingMask = [.width, .minYMargin]
        tabs.segmentStyle = .automatic
        tabs.target = self
        tabs.action = #selector(tabChanged)
        content.addSubview(tabs)

        webContainer.frame = NSRect(x: 0, y: 0, width: frame.width, height: frame.height - topInset)
        webContainer.autoresizingMask = [.width, .height]
        content.addSubview(webContainer)

        panel.contentView = content

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
        previousApp = NSWorkspace.shared.frontmostApplication
        queryField.stringValue = selection

        let request = viewModel?.open(selection: selection)
        tabs.selectedSegment = viewModel?.activeIndex ?? 0
        showActiveWebView()
        if let request { execute(request) }

        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(queryField)
        queryField.selectText(nil)
    }

    func dismiss() {
        guard !isDismissing, panel.isVisible else { return }
        isDismissing = true
        panel.orderOut(nil)
        previousApp?.activate()
        isDismissing = false
    }

    // MARK: - Setup

    /// Build the tab bar and one WKWebView per Source. Rebuilt only when the set
    /// of Sources changes (the dynamic Source store arrives in a later slice).
    private func setupIfNeeded(for sources: [Source]) {
        if let vm = viewModel, vm.sources == sources { return }

        viewModel = PanelViewModel(sources: sources)

        webViews.forEach { $0.removeFromSuperview() }
        webViews = sources.map { _ in
            let webView = WKWebView(frame: webContainer.bounds)
            webView.autoresizingMask = [.width, .height]
            webView.navigationDelegate = self
            webView.isHidden = true
            webContainer.addSubview(webView)
            return webView
        }

        tabs.segmentCount = sources.count
        for (i, source) in sources.enumerated() {
            tabs.setLabel(source.name, forSegment: i)
        }
    }

    // MARK: - Actions

    @objc private func submit() {
        guard let request = viewModel?.submit(query: queryField.stringValue) else { return }
        execute(request)
    }

    @objc private func tabChanged() {
        let index = tabs.selectedSegment
        showActiveWebView(index: index)
        if let request = viewModel?.switchTo(index) { execute(request) }
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
