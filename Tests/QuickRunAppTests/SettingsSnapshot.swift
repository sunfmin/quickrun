import AppKit
import Carbon.HIToolbox
import QuickRunKit
import QuickRunUI
@testable import QuickRun

/// Renders the Settings window's content to PNGs offscreen so its look can be
/// reviewed (and fed to a design pass) without launching the app. Driven by
/// `SettingsSnapshotTests`.
///
/// Reusable glue: it builds the *real* `SettingsWindowController` and feeds it mock
/// data at the lowest seam — three stores backed by an ephemeral `UserDefaults`
/// suite. Everything above runs for real: the controller's own `buildUI`, its table
/// data source, `HotkeyFormatter`, the save-location formatting. Nothing about the
/// window is re-implemented here. The only injected stub is the accessibility check
/// (a non-injectable system call), forced granted so the render is deterministic.
///
/// The window's translucent titlebar can't render offscreen, so the controller's
/// content view is reparented onto a solid `windowBackgroundColor` host — a faithful
/// stand-in for layout and colour review.
enum SettingsSnapshot {
    static let exampleSources: [Source] = [
        Source(name: "有道词典", urlTemplate: "https://dict.youdao.com/result?word={q}&lang=en"),
        Source(name: "Google", urlTemplate: "https://www.google.com/search?q={q}"),
        Source(name: "Wikipedia", urlTemplate: "https://en.wikipedia.org/wiki/Special:Search?search={q}"),
        Source(name: "GitHub", urlTemplate: "https://github.com/search?q={q}"),
    ]

    /// ⌥D — formatted by the real `HotkeyFormatter` into the button title.
    static let exampleHotkey = Hotkey(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(optionKey))
    static let exampleSaveLocation = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        .appendingPathComponent("Desktop", isDirectory: true)

    /// Render `settings-light.png` and `settings-dark.png` into `directory`.
    static func render(toDirectory directory: String) {
        let dir = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for (suffix, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let appearance = NSAppearance(named: appearanceName)!
            let (host, _) = pose(appearance: appearance)
            SnapshotImage.write(host, to: dir.appendingPathComponent("settings-\(suffix).png"))
        }
    }

    /// Build the real controller over ephemeral, example-seeded stores, then reparent
    /// its content view onto an appearance-tracking host. Returns the host (to render)
    /// and the controller (retained, and for content assertions on the real controls).
    static func pose(appearance: NSAppearance) -> (host: NSView, controller: SettingsWindowController) {
        let suite = "QuickRun.snapshot.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite) // start clean

        let sourceStore = UserDefaultsSourceStore(defaults: defaults)
        sourceStore.replaceAll(exampleSources)
        let hotkeyStore = HotkeyStore(defaults: defaults)
        hotkeyStore.save(exampleHotkey)
        let saveLocationStore = SaveLocationStore(defaults: defaults)
        saveLocationStore.setFolder(exampleSaveLocation)

        let controller = SettingsWindowController(
            store: sourceStore,
            hotkeyStore: hotkeyStore,
            saveLocationStore: saveLocationStore,
            defaultHotkey: exampleHotkey,
            onHotkeyChanged: {},
            isAccessibilityGranted: { true }
        )

        let content = controller.contentViewForTesting!
        content.removeFromSuperview()
        let host = windowBackgroundHost(content, appearance: appearance)
        controller.tableView.layoutSubtreeIfNeeded()
        return (host, controller)
    }
}
