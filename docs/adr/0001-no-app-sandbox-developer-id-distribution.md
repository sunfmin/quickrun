# No App Sandbox; distribute via Developer ID + notarization

QuickRun must read the Selection from other apps (Accessibility API plus a synthetic Cmd+C) and listen for a system-wide hotkey. The App Sandbox forbids cross-app Accessibility access and synthetic event posting, so we deliberately do **not** enable the sandbox.

Consequence: the app cannot ship on the Mac App Store. We distribute as a Developer ID-signed, notarized build via direct download. Revisiting this (e.g. to reach the App Store) would require a fundamentally different capture model — clipboard-only, no background capture — and is treated as a redesign, not a config toggle.
