# Capture screen regions via the `screencapture` CLI, not ScreenCaptureKit

For the no-Selection screenshot path we shell out to macOS's `screencapture -i`
(writing to a temp PNG we then load into the Editor) instead of using
ScreenCaptureKit's `SCScreenshotManager`. The decisive reason is permissions:
user-initiated interactive capture through the system tool does **not** require
the app to hold Screen Recording (TCC) access, so we keep QuickRun's
minimal-permission story (Accessibility only — see ADR 0001) and avoid a new
consent prompt. It also needs no macOS 14 floor and lets the OS draw a region
UI that already handles multi-display and Retina correctly.

## Consequences

- We give up control over the selection UI (can't theme it), an in-memory
  capture pipeline (we round-trip through a temp file), and the freeze-and-mark
  -up-in-place model. The Editor is therefore a separate window over a captured
  still, not an overlay on the live screen.
- Moving to ScreenCaptureKit later (e.g. for in-place markup or a custom
  selector) is a redesign, not a swap: it adds a Screen Recording permission and
  raises the minimum macOS version.
- The "interactive capture needs no Screen Recording grant" assumption must be
  re-verified on each new macOS major; if Apple tightens it, revisit this ADR.
