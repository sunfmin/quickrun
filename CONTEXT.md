# QuickRun

A macOS menu-bar utility driven by one global hotkey. With text selected in the frontmost app, it looks that text up across configured web Sources. With nothing selected, it instead captures a screen region the user can OCR into a lookup, mark up, and save.

## Language

**Selection**:
The text highlighted in the frontmost application at the instant the hotkey fires. Captured via the Accessibility API, falling back to a simulated copy. It seeds the Query but is not the same thing.
_Avoid_: clipboard, copied text (the clipboard is only a fallback mechanism, not the concept)

**Query**:
The text in the Panel's input field — what actually gets substituted into each Source's URL. Seeded from a Selection or a Recognized word, but freely editable; pressing return re-runs every Source against the new value.
_Avoid_: search term, keyword, input

**Source**:
One configured lookup target — a display name plus a URL template containing a placeholder for the Selection (e.g. 必应词典 → `https://cn.bing.com/dict/search?q={q}`). The app holds one or many.
_Avoid_: link, site, provider

**Panel**:
The window that appears on the hotkey. Shows one tab per Source; each tab embeds the rendered page for that Source.
_Avoid_: popup, popover, window

## Capture

**Capture**:
The screenshot image of a screen region the user selects when the hotkey fires with no Selection. Unlike a Selection it is pixels, not text — text is recovered from it by OCR.
_Avoid_: screenshot, image, snapshot

**Recognized word**:
A distinct word OCR found in the Capture, listed in the Editor. Choosing one becomes the Query and looks it up immediately — the screenshot counterpart of a Selection.
_Avoid_: token, OCR result, label

**Editor**:
The window that presents a Capture: it lists the Recognized words for lookup, hosts Markup of the Capture, and saves the Capture to the clipboard or a file. Distinct from the Panel, which only renders Sources.
_Avoid_: markup window, preview, canvas

**Markup**:
The arrows, boxes, text, strokes, and redactions the user lays over a Capture in the Editor. Each is an editable object until the Capture is saved, when they are flattened into the pixels.
_Avoid_: annotation, drawing, overlay
