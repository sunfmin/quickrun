# Scroll capture: a fixed Main Box over live content, mirrored in a Scroll Preview

Status: accepted — amends ADR 0003 for the scroll-capture case only.

ADR 0003 made every Capture happen *in place*, over one frozen snapshot of the
screen. Scroll capture is the deliberate exception: the content the user wants is
taller than the screen, so no single frozen frame holds it. The user draws a
region, then scrolls the **live** content through that fixed region while QuickRun
grabs frames and stitches them into one tall Scroll Capture, shown live in a
**Scroll Preview** pane beside the region. It is copied or saved — not OCR'd or
marked up.

## Why it can't reuse the frozen overlay

The in-place model depends on one still: freeze the screen, draw the selector and
Markup over it, flatten cropped to the region. A taller-than-screen Capture
breaks both ends — the source can't be a single still (the content must scroll to
exist), and the result can't be shown in place (it exceeds the display). So scroll
capture needs live content and its own surface.

## The model

1. **Draw, then switch.** The user draws the region in the normal (frozen) Editor,
   then taps the scroll-capture tool. There is no separate scroll-capture entry —
   it reuses the Editor's region drawing.
2. **Unfreeze, keep the Main Box.** The frozen overlay is removed so the real app
   is live again; the **Main Box** stays drawn at the same screen coordinates as a
   thin, **click-through outline** (no dimming), so the user's scroll reaches the
   app beneath it. The box is **locked** — no resize or move — for the run.
3. **User scrolls freely; QuickRun grabs and assembles.** Each frame is a
   ScreenCaptureKit grab of the Main Box, reduced to **row descriptors** (a small
   vector of block averages per pixel row). Frames are assembled by a **vertical
   mosaic** (`ScrollMosaic`), not a one-way append: each frame is aligned against
   the page captured so far, near where the previous frame sat, and may grow the
   page off the **top or bottom**. So the user can scroll **up and down at will** —
   scrolling up attaches new rows above; scrolling back over seen content is
   recognised as a repeat and dropped, never duplicated. The user scrolls —
   QuickRun does **not** synthesize scrolls. The match is **tolerant** (real rows
   never byte-match after subpixel resampling), and all the maths is pure
   (`ScrollMosaic` / `ScrollStitcher` / `RowSignature` in QuickRunKit), testable
   with synthetic arrays.
4. **Scroll Preview.** A pane beside the Main Box (right, or left when there's no
   room) shows the *whole* Scroll Capture live, with **no scrollbar**: it grows to
   fill the available screen height (downward, and upward if there's room), then
   scales the whole image down and narrows so the entire stitch stays visible.
5. **Finish.** **Copy** (to clipboard) and **Save** (to file) each freeze the
   stitch and act — they double as "done." **Esc** cancels and keeps nothing.

## Decisions and the alternatives rejected

- **Non-in-place** (amends ADR 0003): the stitched image exceeds the screen, so it
  can't be shown where it was captured. Accepted as the one Capture path not in
  place.
- **The user scrolls; no `CGEvent` injection.** Rejected synthesizing scroll-wheel
  events: injection is fragile (scroll sign vs the natural-scroll setting,
  cursor-warp coordinate flips, routing to the wrong window). A person scrolling
  their own content is robust and predictable, and needs no input-synthesis grant.
- **A live, fit-to-screen Scroll Preview with no scrollbar** — rejected a
  scrollable post-capture window (an earlier build). Showing the *whole* stitch as
  it grows gives continuous feedback on how much has been captured; a scrollbar and
  a separate review window add chrome without adding that feedback. The cost: the
  preview must rescale every frame as it grows, and very long Captures render tiny.
- **View-only — copy and save, no OCR or Markup.** A Scroll Capture is for
  grabbing long content to keep or paste, not to annotate. Marking up or looking
  up words on a taller-than-screen image would mean a toolbar, Recognized-word
  hit-testing, and a Markup coordinate space inside a scaled pane — large, and not
  what the feature is for. If the user wants those, a Single-screen Capture in the
  Editor still offers them.

## Consequences

- There are two Capture surfaces: the in-place **Editor** for a Single-screen
  Capture (ADR 0003), and the **Scroll Preview** for a Scroll Capture (this ADR).
  The Editor's scroll-capture tool launches the second.
- The frozen-screen point space of ADR 0003 doesn't apply to the stitched image,
  which has its own capture space (its full pixel height).
- Screen Recording permission (already required by ADR 0003) covers the grabs. No
  input is synthesized, so no grant beyond ADR 0001/0003 is needed.
- **Known risk** (not fully solved by the mosaic): sticky headers/footers that
  repeat across frames can match the wrong band, and scrolling faster than a screen
  per grab interval leaves no overlap, so that frame can't be aligned and is dropped
  (content between frames is lost until the user scrolls back over it). Tolerant,
  block-averaged matching absorbs subpixel resampling; the user-driven pace, a short
  grab interval, and anchoring the search near the last position mitigate the rest.
  The thresholds are tuned against real targets.
