# Overview product requirements

## Complete previews before reveal

Super+D must reveal a composed overview with its window and desktop previews
already rendered. Buffer arrival alone is insufficient: the GPU texture must
be ready before the first visible overview frame.

- Reveal the wallpaper, grid, sidebar, labels, and controls together. Do not
  show an incomplete view while captures catch up.
- Do not fade previews in individually, flash empty thumbnails, or replace
  placeholder icons with delayed captures after revealing the overview.
- A timeout is not permission to omit a preview. An unavailable source may
  use a stable fallback only when it cannot be captured, not merely because
  capture is slow.
- Keep the completed composition intact throughout the closing animation.
- Escape and Super+D must still cancel an opening that is waiting on captures.

## Opening latency

The goal is an imperceptible opening delay, including on very slow processors
and CPUs throttled to 400 MHz. This is a product target, not a measured guarantee.
Improve capture, rendering, reuse, and scheduling instead of reducing visual
completeness to make a latency number smaller.

Reuse completed previews and prepared layout across openings. A retained real
preview may be used for the first frame and refreshed normally after opening;
it must not become an icon or blank surface during refresh. Avoid expensive
work on the keypress path and duplicate exports for the same window.

Bound retained resources to relevant windows and outputs, release closed
windows and removed outputs, and pause background capture when the overview is
closed. Any future prewarming must have a measured CPU and memory budget.

## Acceptance evidence

Measure cold and repeated openings separately, including slow-CPU scenarios.
Record keypress-to-first-complete-frame latency, pending previews at reveal,
capture requests, and retained memory. All capturable previews must be rendered
at reveal. Inspect opening and closing recordings for flashing; a successful
IPC reply or an interactive placeholder is not a passing visual latency test.

Sleeping or locked outputs are not valid visual benchmarks. Report them
separately, and do not claim a speedup measured only on an unthrottled CPU as a
400 MHz result.
