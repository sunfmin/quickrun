# In-place capture via a self-drawn overlay over a frozen screen

Status: accepted — supersedes ADR 0002.

The Capture experience moved to a Shottr/CleanShot-style model: the region is
selected, marked up, and read in place, where the content sits on screen,
rather than in a separate window. Positioning anything in place requires knowing
the selected rectangle's screen coordinates, which `screencapture -i` (ADR
0002's basis) never reports. So QuickRun now freezes the whole screen with
ScreenCaptureKit (macOS 14+) and draws its own region selector and Markup
surface over that frozen snapshot — which means accepting the **Screen
Recording** permission that ADR 0002 was written to avoid.

## Considered alternatives

- **Keep `screencapture -i`** (ADR 0002): no Screen Recording permission, but the
  selection coordinates are unknowable, so "in place" is impossible — rejected
  because it defeats the redesign's whole point.
- **Approximate placement** (capture via `screencapture -i`, show the result at
  the cursor): avoids the permission but the position is guessed, not the true
  capture rect — rejected as off-feeling.

## Consequences

- First run now asks for two permissions — Accessibility (hotkey + Selection,
  ADR 0001) and Screen Recording (the frozen snapshot). Every comparable
  screenshot tool requires the latter, so it is expected, not alarming.
- Still no App Sandbox and still not App-Store-eligible (ADR 0001 unchanged).
- QuickRun now owns the region-selection UI, multi-display handling, and Retina
  scaling that the OS tool previously handled for free.
- The `screencapture` CLI dependency and the assumption in ADR 0002 about
  interactive capture needing no grant are retired.
