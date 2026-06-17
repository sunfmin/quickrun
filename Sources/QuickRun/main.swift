import AppKit

// Menu-bar accessory app: no Dock icon, no app-switcher presence (ADR: see CONTEXT).
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
