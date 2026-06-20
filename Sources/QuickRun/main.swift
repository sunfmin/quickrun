import AppKit
import QuickRunUI

// Dev-only: render the toolbars to PNGs and exit, without launching the app.
let arguments = CommandLine.arguments
if let flag = arguments.firstIndex(of: "--snapshot-toolbar"), flag + 1 < arguments.count {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    ToolbarSnapshot.render(toDirectory: arguments[flag + 1])
    exit(0)
}

// Menu-bar accessory app: no Dock icon, no app-switcher presence (ADR: see CONTEXT).
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
