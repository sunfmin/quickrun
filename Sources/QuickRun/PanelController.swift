import AppKit
import WebKit
import QuickRunKit

/// The Panel: an editable Query field on top of a `WKWebView` that performs
/// top-level navigation to the built URL (not an HTML iframe, so
/// X-Frame-Options / CSP frame-ancestors restrictions don't apply).
///
/// Spotlight-style lifecycle: it appears centered and floating, activates the
/// app for key input, dismisses on Esc or click-away (resigning key), and
/// returns focus to the app that was frontmost before it opened.
final class PanelController: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let webView: WKWebView
    private let queryField = NSTextField()
    private var source: Source?
    private weak var previousApp: NSRunningApplication?
    private var escMonitor: Any?
    private var isDismissing = false

    override init() {
        let frame = NSRect(x: 0, y: 0, width: 820, height: 620)
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: frame.width, height: frame.height - 44))
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

        webView.autoresizingMask = [.width, .height]
        content.addSubview(webView)

        queryField.frame = NSRect(x: 8, y: frame.height - 36, width: frame.width - 16, height: 28)
        queryField.autoresizingMask = [.width, .minYMargin]
        queryField.placeholderString = "Look up…"
        queryField.font = .systemFont(ofSize: 15)
        queryField.target = self
        queryField.action = #selector(submit)
        content.addSubview(queryField)

        panel.contentView = content

        // Esc dismisses while the Panel is visible. A local monitor is more
        // reliable than -cancelOperation: when a WKWebView holds first responder.
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible, event.keyCode == 53 else { return event }
            self.dismiss()
            return nil
        }
    }

    deinit {
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
    }

    /// Show the Panel for `source`, seeding the Query field from `selection`.
    /// A non-empty Selection triggers an immediate lookup; an empty one leaves
    /// the focused field blank and performs no navigation.
    func present(selection: String, source: Source) {
        self.source = source
        previousApp = NSWorkspace.shared.frontmostApplication
        queryField.stringValue = selection

        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(queryField)
        queryField.selectText(nil)

        if !selection.isEmpty { loadCurrentQuery() }
    }

    /// Hide the Panel and hand keyboard focus back to the previously active app.
    func dismiss() {
        guard !isDismissing, panel.isVisible else { return }
        isDismissing = true
        panel.orderOut(nil)
        previousApp?.activate()
        isDismissing = false
    }

    @objc private func submit() {
        loadCurrentQuery()
    }

    /// Build a URL from the current Query field contents and load it.
    private func loadCurrentQuery() {
        guard let source else { return }
        let query = queryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let url = try? URLBuilder.build(source: source, query: query) else { return }
        webView.load(URLRequest(url: url))
    }

    // Click-away: the Panel lost key focus, so dismiss it.
    func windowDidResignKey(_ notification: Notification) {
        dismiss()
    }
}
