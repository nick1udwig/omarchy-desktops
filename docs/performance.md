# Exposé performance

Measured on 2026-09-04 with Quickshell 0.3.1 and the installed three-monitor Hyprland session: a 1.6× laptop display, a landscape external display, and a portrait external display, all around 60 Hz.

## What was expensive

Every grid card and visible sidebar window had an independent continuous `ScreencopyView`. Busy applications therefore drove repeated full-window exports in both places. The grid also rendered each preview into a doubled-size intermediate layer before scaling it down, including with square corners.

`constraintSize` does **not** downscale captured buffers. It only constrains the view's implicit display size, as documented by [Quickshell](https://quickshell.org/docs/v0.3.0/types/Quickshell.Wayland/ScreencopyView/). The [Hyprland capture backend](https://github.com/quickshell-mirror/quickshell/blob/master/src/wayland/screencopy/hyprland_screencopy/hyprland_screencopy.cpp) accepts the compositor's native buffer size. Making a thumbnail smaller alone does not make its export cheaper.

The overview also invalidated every window list on every raw compositor event and again for individual metadata changes. Composition read the complete IPC metadata objects, so title-only updates could rerun the row search even when window identities and dimensions were unchanged.

## Changes

- All previews share one round-robin scheduler, issuing at most one request per 33 ms tick across all monitors. The initial implementation used this same budget for first frames; the startup path was subsequently separated as described below.
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

The remaining fixed cost was exporting native-size buffers independently for each view. The later shared-texture pass below removes the duplicate export within each output, while keeping separate ownership for different output surfaces.

## Layout and maintenance pass, 2026-09-05

The layout now solves the common preview scale directly from each row's width and the combined height. Natural dimensions are computed and sorted once. Positioned rectangles are allocated only for the winning row arrangement, replacing the repeated trial compositions used by the previous binary search.

An isolated Node.js benchmark compared the implementation at `ba3ceb8` with this change. Each case used a 1920×1080 area and repeating aspect ratios 0.45, 1, 1.6, 2.5, and 4. After 50 warm-up calls, five alternating runs of 200 calls per implementation were measured; the table reports median time per call.

| Windows | Previous layout | Direct calculation | Speedup |
| --- | ---: | ---: | ---: |
| 6 | 0.143 ms | 0.012 ms | 12.3× |
| 20 | 0.806 ms | 0.048 ms | 16.8× |
| 60 | 1.440 ms | 0.095 ms | 15.2× |

These results measure JavaScript layout work, not overall frame rate or Quickshell's rendering performance. A separate comparison of 500 deterministic generated cases found no lost feasible layouts, smaller previews, overlap, or viewport overflow. The direct solution can make cards slightly larger by eliminating the old binary search's rounding slack. Regression tests check exact width/height limits, crowded and impossible layouts, and allocating only one final composition.

The same pass removes the unused `WorkspaceTile.qml` / `WindowPreview.qml` implementation and unused card footer modes, loaders, mouse handling, and controller hooks. Grid cards and sidebar previews share `PreviewClip.qml`. Duplicate snapshot text is ignored before parsing or replacing state, unrelated custom IPC events no longer reload the snapshot, and already-native JavaScript arrays are reused during normalization.

The standalone suite and manifest validation pass. Isolated Quickshell checks compiled all overview components, instantiated the card in a hidden window, verified Quick Look geometry and filtering, and confirmed that 100 duplicate snapshots cause no state updates. After reloading in an unlocked session, live checks verified capture content on all three monitors, a shared budget of 31 scheduled requests over one second, search and title updates, Quick Look, desktop moves, capture cleanup, and square/rounded rendering. Pointer checks verified drag cancellation and geometry restoration, zero capture requests during a held drag, dropping onto another desktop’s remembered workspace, and clicking the moved card to activate it. Test windows were closed and the original desktop, focus, cursor position, and rounding restored.

Live testing also exposed a focus problem: keeping one monitor’s layer surface in exclusive keyboard mode prevented pointer events from reaching the other monitors. The selected surface now acquires exclusive focus briefly after mapping and releases it to on-demand mode, following Omarchy’s existing panel behavior. Other surfaces request no keyboard focus until the user selects them. Repeated live checks verified typing without a preliminary click, Tab through all three monitors, search-field clicks on each monitor, and reopening during the close animation.


## Coherent opening and native dragging, 2026-09-06

The previous steady refresh limit also serialized first frames. For example, 20 grid cards and their sidebar copies needed at least 1.32 seconds just to schedule 40 exports, while the opening animation lasted 190 ms. The unready card text and empty sidebar were already visible during that interval.

Startup now fills a shared budget of at most sixteen outstanding first-frame exports, replenished by an 8 ms timer as frames complete. Qt can coalesce these ticks to the display cadence. Existing content is not refreshed during preparation. The sidebar and grid stay transparent until the enabled previews have content, then fade together over 100 ms. The wallpaper animation starts immediately. A 500 ms wall-clock deadline prevents an unresponsive source from blocking the overview; late frames crossfade over a quiet application-icon fallback. Steady refresh limits remain unchanged.

The standalone scheduler tests model 60 previews with 16 ms export latency and verify readiness within the opening animation, bounded concurrency, no duplicate first requests, and stopped/hidden sources releasing the readiness gate. This is a scheduling simulation, not a measurement of compositor or GPU latency.

Window movement now uses native drag-and-drop with a 190-pixel-wide static card image. It crosses Wayland surfaces, unlike the previous internal QML drag. Window areas target the destination monitor’s current workspace, and sidebar items target that monitor and desktop’s remembered workspace. Destination validation and deferred movement are shared, and invalid or cancelled drops leave window membership unchanged.

On the same three-monitor session, twenty disposable animated 800×600 windows produced 25 grid cards and 50 total captures. Three openings prepared every enabled preview in 245, 190, and 205 ms respectively, with zero missing frames at reveal; the shared fade adds 100 ms. These are first-frame readiness measurements, not frame presentation timestamps or a guarantee of 190 ms total opening time. The blurred background and sidebar share a wallpaper decode capped at 1280×1280. Steady capture pacing is unchanged.

A stress fixture with too many tiled windows produced invalid zero-sized surfaces and a Wayland protocol disconnect. Previews now skip invalid or not-yet-known window sizes and release their capture source when dimensions become invalid. The valid-size benchmark used temporary floating probe windows. This guard cannot eliminate a compositor/backend race after the metadata check.

Final native pointer checks passed for a same-monitor desktop drop, a drop into the laptop monitor’s grid, and a desktop drop on the portrait monitor. Completion was observed 70–73 ms after release, including test polling overhead. Escape left the window in place (and closed the overview in this Hyprland session); clicking activated the selected card. All temporary windows were closed and the original focus and cursor restored.

A 60 fps recording of three additional openings, with 26 cards and 52 captures, was inspected for the coherent grid/sidebar fade. All previews were present at reveal (328, 203, and 196 ms while recording). An actual QML timer fixture prepared 60 simulated 16 ms frames in 105 ms and released all views; a stalled fixture revealed at 506 ms instead of waiting indefinitely. Invalid-size checks issued no captures. Reopening during the close animation also retained complete previews, and closing left zero registered captures. All 179 standalone checks and plugin validation pass. Private recordings and window metadata are not committed.


## Painted sidebar frames and shared captures, 2026-09-06

Further inspection found two gaps in the previous reveal gate. A native buffer could report `hasContent` before Qt drew its texture, and zero-opacity ancestors prevented that preparation from completing. Separately, closing immediately cleared the sidebar's models and captures even though the rail was still fading, exposing wallpaper-only thumbnails. A recording showed this closing flash clearly.

Each output now owns one capture per window. Both its card and sidebar copy sample the same rendered texture, using Qt's built-in texture shader. Producers render outside the viewport without inheriting the UI opacity; readiness waits for the texture update to complete. The sidebar retains its models and captures through the closing animation. Reopening during that animation can reverse the fade immediately. Cache eviction is deferred through a UI update so moving between consumers on the same output preserves the frame.

The opening batch now permits 32 outstanding unique sources. Sources start immediately when their consumers attach. Reopening also reuses the wallpaper decode unless its file stamp changed. If a source misses the 500 ms deadline, its icon fallback remains fixed for that opening rather than being replaced after reveal. The shared fade takes 60–100 ms according to preparation time.

With twenty disposable animated windows, 26 sources served 52 placements. Three instrumented openings took 208, 152, and 149 ms to prepare rendered textures, with zero missing sources. The first run was after a shell restart. Repeated openings previously took about 190–245 ms while only checking buffer availability; the new check includes rendering. These are short live-session measurements, not guaranteed latency or GPU/CPU benchmarks.

A separate 60 fps recording spread probe windows across three desktops and monitors. With 30 sources serving 57 placements, all visible sidebar windows had a matching delegate and painted source at reveal; preparation took 306, 158, and 171 ms while recording. Frame inspection confirmed populated thumbnails during opening and retained contents during closing, replacing the previously observed wallpaper-only closing frame. The recording and temporary window metadata remain outside the repository.

Final live interaction checks passed for Quick Look resizing, retaining every sidebar preview through closing, and reopening during the fade with 0 ms preparation. Native drops to another desktop on the same monitor, another monitor's grid, and another monitor's desktop all completed in 70–73 ms including polling overhead. Escape cancellation, click activation, and closing a captured window also passed. Closing the overview released every capture; the test windows were removed and focus and cursor restored. The full test suite and plugin validation pass, with no compositor configuration errors or recent shell runtime errors.
