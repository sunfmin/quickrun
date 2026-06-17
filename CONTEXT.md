# QuickRun

A macOS menu-bar utility that, on a global hotkey, takes the text selected in the frontmost app, substitutes it into one or more configured URL templates, and shows the resulting web pages in an embedded panel.

## Language

**Selection**:
The text highlighted in the frontmost application at the instant the hotkey fires. Captured via the Accessibility API, falling back to a simulated copy. It seeds the Query but is not the same thing.
_Avoid_: clipboard, copied text (the clipboard is only a fallback mechanism, not the concept)

**Query**:
The text in the Panel's input field — what actually gets substituted into each Source's URL. Seeded from the Selection on open, but freely editable; pressing return re-runs every Source against the new value.
_Avoid_: search term, keyword, input

**Source**:
One configured lookup target — a display name plus a URL template containing a placeholder for the Selection (e.g. 必应词典 → `https://cn.bing.com/dict/search?q={q}`). The app holds one or many.
_Avoid_: link, site, provider

**Panel**:
The window that appears on the hotkey. Shows one tab per Source; each tab embeds the rendered page for that Source.
_Avoid_: popup, popover, window
