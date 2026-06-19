# Scroll capture is a non-in-place Capture path

Status: accepted — amends ADR 0003 for the scroll-capture case only.

ADR 0003 made every Capture happen *in place*, over one frozen snapshot of the
screen. Scroll capture is the deliberate exception: the content the user wants is
taller than the screen, so there is no single frozen frame that holds it. The
engine instead scrolls the live target, grabs many frames, and stitches them into
one tall image that, by definition, does not fit where it was captured. That
image is reviewed and marked up in a **scrollable preview window**, not over the
frozen overlay.

## Why it can't reuse the frozen overlay

The in-place model depends on one still: freeze the screen, draw the selector and
Markup over it, flatten cropped to the region. A taller-than-screen Capture
breaks both ends — the source can't be a single still (the content must scroll to
exist), and the output can't be shown in place (it exceeds the display). So
scroll capture needs its own engine and its own surface.

## How it works

- **Frame source.** Repeated ScreenCaptureKit grabs of the chosen region while
  the **user scrolls the live content themselves** (the overlay prompts "Scroll
  the page to capture more"). QuickRun does not synthesize scrolls — chosen over
  injecting `CGEvent` scroll-wheel events because injection is fragile (scroll
  sign vs the natural-scroll setting, cursor-warp coordinate flips, routing to
  the wrong window) and a person scrolling their own content is robust and
  predictable. The driver keeps each frame that adds new rows and drops the
  unchanged ones; Done or Esc finishes. The grab loop is impure app glue.
- **Highest pure seam — `ScrollStitcher`** — works on **row signatures** (one
  hash per pixel row), never raw images, so it is testable with synthetic arrays
  and no ScreenCaptureKit/Vision:
  - `verticalOverlap(between:_:)` — how many rows the later frame shares with the
    earlier one (the earlier frame's matching suffix == the later frame's prefix).
  - `offsets(forFrames:)` — each frame's top y in the stitched image, overlaps
    removed; the app composites the real CGImages at those offsets.
  - end-of-scroll = a frame that adds nothing new (overlap ≈ full frame).
- **Output.** A tall image larger than the screen, shown in a scrollable preview
  window. Markup and export reuse the existing `MarkupDocument` / `MarkupRenderer`
  over that image. OCR on the stitched image reuses the `TextRecognizing` seam.

## Consequences

- There are now two Capture surfaces: the in-place frozen overlay (the default,
  ADR 0003) and the scroll-capture preview window (this ADR). The overlay's
  toolbar launches the scroll path; the result lands in the preview.
- The frozen-screen point space of ADR 0003 does not apply to the stitched image,
  which has its own capture space (its full pixel height). Markup geometry there
  is in that space; flattening is unchanged.
- **Known risk** (not solved by the row-signature approach alone): sub-pixel
  scrolling, sticky headers/footers that repeat across frames, and scrolling
  faster than the grab interval (which can drop content between frames) can fool
  overlap detection. The user-driven model mitigates by letting a person scroll
  at a readable pace; over-sampling (a short grab interval) catches normal speeds.
- Screen Recording permission (already required by ADR 0003) covers the grabs. No
  input is synthesized, so no extra grant is needed beyond ADR 0001/0003.
