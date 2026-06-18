import AppKit
import Carbon.HIToolbox
import QuickRunKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotKey: HotKeyMonitor?
    private var panel: PanelController?
    private var overlay: CaptureOverlayController?

    private let store = UserDefaultsSourceStore(defaults: .standard)
    private let hotkeyStore = HotkeyStore(defaults: .standard)
    private let saveLocationStore = SaveLocationStore(defaults: .standard)
    private lazy var settings = SettingsWindowController(
        store: store,
        hotkeyStore: hotkeyStore,
        saveLocationStore: saveLocationStore,
        defaultHotkey: defaultHotkey,
        onHotkeyChanged: { [weak self] in self?.registerHotkey() }
    )

    // Default hotkey: ⌥D (key code + Carbon modifier mask, matched by code).
    private let defaultHotkey = Hotkey(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(optionKey))

    // First-run defaults; thereafter the user's stored Sources win.
    private let defaultSources = [
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
        store.seedIfEmpty(defaultSources)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = NSImage(systemSymbolName: "text.magnifyingglass", accessibilityDescription: "QuickRun") {
            image.isTemplate = true
            item.button?.image = image
        } else {
            item.button?.title = "QR"
        }
        let menu = NSMenu()
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit QuickRun",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        item.menu = menu
        statusItem = item

        registerHotkey()

        // First-run: ask for Accessibility so capture and the hotkey can work.
        if !AccessibilityPermission.isGranted {
            AccessibilityPermission.prompt()
        }
    }

    /// (Re)register the global hotkey from the stored value, or the default.
    /// Matched by raw key code + modifiers, never the produced character
    /// (⌥D yields the dead key ∂).
    private func registerHotkey() {
        hotKey = nil // unregisters the previous one
        let hotkey = hotkeyStore.load() ?? defaultHotkey
        hotKey = HotKeyMonitor(
            keyCode: hotkey.keyCode,
            modifiers: hotkey.modifiers
        ) { [weak self] in
            self?.trigger()
        }
    }

    @objc private func openSettings() {
        settings.show()
    }

    private func trigger() {
        guard AccessibilityPermission.isGranted else {
            presentPermissionNeeded()
            return
        }
        // When QuickRun itself is frontmost, the system selection lives inside our
        // own Panel. Read it straight from the active web view (no synthetic ⌘C,
        // which the still-held hotkey modifiers would corrupt into a beep).
        if NSApp.isActive, let controller = panel, controller.isVisible {
            controller.lookUpSelectionInActiveWebView()
            return
        }
        let selection = capturer.capture() ?? ""
        // Nothing selected: there is no word to look up, so capture a screen
        // region instead of opening a Panel to type into.
        guard !selection.isEmpty else {
            startCapture()
            return
        }
        let controller = panel ?? PanelController()
        controller.onOpenSettings = { [weak self] in self?.openSettings() }
        panel = controller
        controller.present(selection: selection, sources: store.load())
    }

    /// Freeze the screen and open the in-place Editor overlay (ADR 0003). First
    /// use needs Screen Recording permission; without it, guide the user the same
    /// way the Accessibility prompt does and do nothing else.
    private func startCapture() {
        guard ScreenCapturePermission.isGranted else {
            ScreenCapturePermission.request()
            presentScreenRecordingNeeded()
            return
        }
        DisplayFreezer.freezeDisplayUnderCursor { [weak self] frozen in
            guard let self, let frozen else { return }
            let overlay = CaptureOverlayController(frozen: frozen)
            overlay.onClosed = { [weak self] in self?.overlay = nil }
            self.overlay = overlay
            overlay.show()
        }
    }

    private func presentScreenRecordingNeeded() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "QuickRun needs Screen Recording permission"
        alert.informativeText = "Grant Screen Recording access so QuickRun can freeze the screen to capture a region. You may need to quit and reopen QuickRun after granting."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            ScreenCapturePermission.openSettingsPane()
        }
    }

    private func presentPermissionNeeded() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "QuickRun needs Accessibility permission"
        alert.informativeText = "Grant Accessibility access so QuickRun can read the selected text and use the global hotkey."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            AccessibilityPermission.openSettingsPane()
        }
    }
}
