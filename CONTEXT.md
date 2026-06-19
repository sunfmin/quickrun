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
The pixels the user works with when the hotkey fires with no Selection — at minimum copied or saved; a Single-screen Capture can also be OCR'd and marked up. Unlike a Selection it is pixels, not text. Acquired two ways: a Single-screen Capture or a Scroll Capture.
_Avoid_: screenshot, image, snapshot

**Single-screen Capture**:
A Capture of one screenful — the region of the frozen screen the user selects in the Editor, in place where the content sits. Supports the full Editor: Recognized words, Markup, copy, save.
_Avoid_: region capture

**Scroll Capture**:
A Capture taller than the screen, stitched from frames grabbed while the user scrolls the live content under the Main Box. Reviewed in the Scroll Preview and copied or saved as-is — no OCR or Markup.
_Avoid_: long screenshot, scrolling screenshot

**Main Box**:
The region the user draws that, during a Scroll Capture, stays fixed over the live content while the content scrolls through it — the sampling window each frame is grabbed from. Its width is the Scroll Capture's width; its height is one frame, not the stitched whole.
_Avoid_: capture region (during scroll capture specifically), viewport

**Scroll Preview**:
The pane beside the Main Box that shows the whole Scroll Capture at once as it accumulates — never a scrollbar. It grows taller at the Main Box's width as the user scrolls; once it would exceed the screen's height it scales the whole image down and narrows, so the entire stitch stays visible. Carries its only two actions — copy to clipboard, save to file. A distinct surface from the Editor: not in place, view-only.
_Avoid_: preview window, editor, scroll view

**Recognized word**:
A word OCR found in the Capture, drawn as live clickable text on it: hovering highlights the word, clicking makes it the Query and looks it up immediately — the screenshot counterpart of a Selection.
_Avoid_: token, OCR result, label

**Editor**:
The full-screen overlay that freezes the screen so the user can select the Capture, mark it up, click its Recognized words to look them up, and copy or save it — all in place, where the content sits. Not a separate window.
_Avoid_: editor window, preview, canvas

**Markup**:
The arrows, boxes, text, strokes, and redactions the user lays over a Capture in the Editor. Each is an editable object until the Capture is copied or saved, when they are flattened into the pixels.
_Avoid_: annotation, drawing
