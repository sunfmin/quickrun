import AppKit
import Carbon.HIToolbox
import QuickRunKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotKey: HotKeyMonitor?
    private var panel: PanelController?

    // Hardcoded Sources for now; replaced by the SourceStore in a later slice.
    private let sources = [
        Source(name: "必应词典", urlTemplate: "https://cn.bing.com/dict/search?q={q}"),
        Source(name: "有道词典", urlTemplate: "https://dict.youdao.com/result?word={q}&lang=en"),
        Source(name: "Google", urlTemplate: "https://www.google.com/search?q={q}"),
    ]

    // Accessibility first; fall back to a simulated copy + clipboard read.
    private lazy var capturer: SelectionCapturer = ChainedSelectionCapturer([
        AXSelectionCapturer(reader: SystemAccessibilityReader()),
        ClipboardSelectionCapturer(
            pasteboard: SystemPasteboard(),
            copy: SystemCopy.copySelection
        ),
    ])

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "QR"
        let menu = NSMenu()
        menu.addItem(
            withTitle: "Quit QuickRun",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        item.menu = menu
        statusItem = item

        // Default hotkey: ⌥D. Matched by raw key code + modifiers, never the
        // produced character (⌥D yields the dead key ∂).
        hotKey = HotKeyMonitor(
            keyCode: UInt32(kVK_ANSI_D),
            modifiers: UInt32(optionKey)
        ) { [weak self] in
            self?.trigger()
        }
    }

    private func trigger() {
        let selection = capturer.capture() ?? ""
        let controller = panel ?? PanelController()
        panel = controller
        controller.present(selection: selection, sources: sources)
    }
}
