import AppKit

// Menu-bar accessory app: no Dock icon, no app-switcher presence (ADR: see CONTEXT).
// Offscreen UI snapshots (settings / panel / toolbars) now render from the test
// target — see QuickRunAppTests and QUICKRUN_SNAPSHOT_DIR.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
