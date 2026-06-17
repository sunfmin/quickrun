import AppKit
import WebKit

/// The Panel: a floating window hosting a `WKWebView` that performs top-level
/// navigation to the built URL (not an HTML iframe, so X-Frame-Options / CSP
/// frame-ancestors restrictions don't apply).
///
/// Spotlight-style lifecycle: it appears centered and floating, activates the
/// app for key input, dismisses on Esc or click-away (resigning key), and
/// returns focus to the app that was frontmost before it opened.
final class PanelController: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let webView: WKWebView
    private weak var previousApp: NSRunningApplication?
    private var escMonitor: Any?
    private var isDismissing = false

    override init() {
        let frame = NSRect(x: 0, y: 0, width: 820, height: 620)
        webView = WKWebView(frame: frame)
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
        panel.contentView = webView

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

    /// Load `url` as a top-level navigation and bring the Panel forward.
    func show(url: URL) {
        previousApp = NSWorkspace.shared.frontmostApplication
        webView.load(URLRequest(url: url))
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    /// Hide the Panel and hand keyboard focus back to the previously active app.
    func dismiss() {
        guard !isDismissing, panel.isVisible else { return }
        isDismissing = true
        panel.orderOut(nil)
        previousApp?.activate()
        isDismissing = false
    }

    // Click-away: the Panel lost key focus, so dismiss it.
    func windowDidResignKey(_ notification: Notification) {
        dismiss()
    }
}
