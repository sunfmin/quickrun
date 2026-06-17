import AppKit
import WebKit

/// The Panel: a floating window hosting a `WKWebView` that performs top-level
/// navigation to the built URL (not an HTML iframe, so X-Frame-Options / CSP
/// frame-ancestors restrictions don't apply).
final class PanelController {
    private let panel: NSPanel
    private let webView: WKWebView

    init() {
        let frame = NSRect(x: 0, y: 0, width: 820, height: 620)
        webView = WKWebView(frame: frame)
        panel = NSPanel(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "QuickRun"
        panel.isFloatingPanel = true
        panel.contentView = webView
    }

    /// Load `url` as a top-level navigation and bring the Panel forward.
    func show(url: URL) {
        webView.load(URLRequest(url: url))
        NSApp.activate(ignoringOtherApps: true)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }
}
