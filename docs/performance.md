# Exposé performance

Measured on 2026-09-04 with Quickshell 0.3.1 and the installed three-monitor Hyprland session: a 1.6× laptop display, a landscape external display, and a portrait external display, all around 60 Hz.

## What was expensive

Every grid card and visible sidebar window had an independent continuous `ScreencopyView`. Busy applications therefore drove repeated full-window exports in both places. The grid also rendered each preview into a doubled-size intermediate layer before scaling it down, including with square corners.

`constraintSize` does **not** downscale captured buffers. It only constrains the view's implicit display size, as documented by [Quickshell](https://quickshell.org/docs/v0.3.0/types/Quickshell.Wayland/ScreencopyView/). The [Hyprland capture backend](https://github.com/quickshell-mirror/quickshell/blob/master/src/wayland/screencopy/hyprland_screencopy/hyprland_screencopy.cpp) accepts the compositor's native buffer size. Making a thumbnail smaller alone does not make its export cheaper.

The overview also invalidated every window list on every raw compositor event and again for individual metadata changes. Composition read the complete IPC metadata objects, so title-only updates could rerun the row search even when window identities and dimensions were unchanged.

## Changes

- All previews share one round-robin scheduler, issuing at most one request per 33 ms tick across all monitors. First frames use the same budget, avoiding a burst of exports when opening.
- Cards request updates every 200 ms, sidebar previews every 1000 ms, and Quick Look every 66 ms. These are maximum requested rates; the shared budget lowers individual rates when more windows compete. Animation timing remains independent of capture timing.
- Dragging and closing pause capture. Filtered cards retain their last frame without requesting more; offscreen sidebar delegates release their captures. Closed surfaces release all capture delegates.
- Only windows in the current workspace get grid delegates. Other desktops' visible sidebar previews still work.
- Previews sample the exported texture directly. Square previews allocate neither the extra intermediate layer nor a rounded mask.
- Property bindings track membership and search dependencies directly. A primitive aspect-ratio signature isolates composition from title-only IPC changes.

## Live comparison

Each sample ran for eight seconds after a two-second settling period, with six visible windows including a disposable 1000×700 animated Quickshell window. CPU was calculated from `/proc/<pid>/stat` deltas for the existing shell and compositor, excluding the separate animation process. Percentages are relative to one CPU core.

| Process | Before | After | Reduction |
| --- | ---: | ---: | ---: |
| Omarchy shell | 28.2% | 5.4% | 81% |
| Hyprland | 17.4% | 7.7% | 56% |

These are short measurements in an active desktop, not an isolated benchmark. Window placement and unrelated application activity can vary. They demonstrate reduced work in this session; they do not establish frame latency, GPU utilization, or a guaranteed speedup on other hardware.

Live checks confirmed captured content on every grid card, shared request pacing, title changes updating active search, Quick Look entry/exit, moving a disposable window to another desktop and back, and zero registered captures or further requests after closing. Reopening with rounding 18 retained preview content on every monitor; square and rounded screenshots were inspected. Original rounding was restored, and test windows were closed. Private captures and window metadata are not committed.

`./test/run` includes scheduler tests with 60 competing previews, refresh deadlines, disabled and pending sources, and removal around the queue cursor. Existing layout checks cover bounds and overlap across landscape, portrait, and small surfaces.

To inspect a running session, use `omarchy-shell desktops-overview status`. Its `captures` object reports `active`, `views`, and cumulative `requests`. Compare request counts over a known interval with the overview open and then closed. Requests can be no-ops when Quickshell already has a capture pending for compositor damage; the counter measures scheduled calls, not completed frames.

The remaining fixed cost is exporting native-size buffers. Sharing one exported buffer between a grid card and its sidebar copy could reduce this further, but requires additional texture ownership across surfaces or support in the capture backend. The scheduler bounds the current implementation's work without that dependency.
