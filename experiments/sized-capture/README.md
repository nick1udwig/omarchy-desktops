# Per-request capture sizes: integration draft

This is the next step after the [global-divisor experiment](../scaled-capture/README.md):
a matched protocol, Hyprland implementation, and Quickshell API. An Omarchy
configuration alone cannot make the existing compositor export smaller buffers.

The three review units are:

| Component | Change |
| --- | --- |
| hyprland-protocols | A draft `capture_toplevel_with_size` request, with maximum width and height in physical buffer pixels |
| Hyprland | Fit each frame within its requested bounds and render directly into that smaller buffer; retain native session constraints |
| Quickshell | `ScreencopyView.captureSize`, applied to future requests without destroying the existing image |

`WindowCapture.qml` requests the largest consumer's physical texture size, using
the existing 64-pixel allocation steps. Requests still follow the shared capture
budget. Layout changes do not independently initiate captures. The existing GPU
texture readiness gate remains in place, and retained previews stay available
during refresh. Stock Quickshell ignores this optional integration; a patched
Quickshell talking to a version-2 compositor falls back to native resolution.

## Protocol and API semantics

- `(0, 0)` requests native size. Zero on just one axis leaves that axis unbounded.
- Fit the entire image, preserve aspect ratio to integer-pixel precision, never
  upscale, and keep each dimension at least one pixel.
- Buffer events remain authoritative: clients allocate exactly the advertised size.
- Bounds belong to a single frame, not its source or session. Native and scaled
  captures of the same window can coexist, including on one Wayland connection.
- Existing requests retain native resolution. Output capture is unchanged.
- `captureSize` is a hint on unsupported Quickshell backends. Negative QML
  dimensions normalize to zero. `sourceSize` reports the actual returned size.
- Changing `captureSize` retains `hasContent` and does not itself request a frame.
  An outstanding request keeps its original bounds; another `captureFrame()`
  during that request is coalesced by the existing backend. The next request
  uses the latest size. `frameCaptured` reports arrival, not GPU readiness.
- Permission checks and the existing rendering path remain in use. A pending
  permission snapshot stays native-sized because it is shared across requests.
- Export render-pass clipping uses the source image's bounds. The existing
  monitor-based clip truncated captures of windows larger than a rotated output,
  at both native and reduced resolution. Occlusion simplification stays enabled.
- Window buffers are cleared in unrotated buffer coordinates, including when
  reusing an opaque frame's buffer for a transparent frame on a rotated output.

**The version-3 opcode here is an experimental draft, not an upstream allocation.**
Use only the matched builds in isolated tests. Upstream must agree on the wire
interface/version (or a separate protocol) before shipping this in Omarchy. Do
not install a client that assumes this draft opcode on arbitrary future servers.

## Reproduce

`build.sh [directory]` clones pinned sources, checks their revisions, applies
the three patches, and builds both executables. It never installs Hyprland or
Quickshell into the desktop. Normal Hyprland/Quickshell development dependencies
must already be available; CLI11, Vulkan headers, and Ninja are built locally.
Quickshell's optional crash reporter is disabled to avoid requiring cpptrace.
Ninja avoids a generated D-Bus dependency-order failure with Makefiles in this
Quickshell/Qt combination. Builds use Release and four low-priority jobs by default.

```sh
bash experiments/sized-capture/build.sh /tmp/omarchy-sized-capture
```

Use the shared disposable-compositor harness. It creates its own Wayland and
Hyprland IPC sockets and synthetic source windows; it does not benchmark private
desktop window contents. The nested backend briefly creates a host window,
then moves the experiment to a GPU-backed headless output.

```sh
python3 experiments/scaled-capture/run.py \
  --binary /tmp/omarchy-sized-capture/Hyprland/build/Hyprland \
  --quickshell /tmp/omarchy-sized-capture/quickshell/build/src/quickshell \
  --per-request --divisors 1 8 --windows 1 32 64 --runs 6 --warm \
  --output /tmp/sized-capture-benchmark
```

`--per-request` translates the divisors into per-request bounds in the staged
consumer; the new server has no global divisor setting. Use `--production-size
--divisors 1` to exercise the production texture-size calculation unmodified.
Use `--api --divisors 1 --windows 1` for concurrent sizes, aspect fitting,
in-flight size changes, cancellation, and retained-content assertions. Add
`--legacy-server` and use `/usr/bin/Hyprland` to verify native fallback. Run the
new server with `/usr/bin/qs --divisors 1` to check legacy clients.

The same harness supports `--shm`, `--transparent`, `--scale 1.6 --transform 1`, odd dimensions,
`--subsurface`, and `--trace`. Pixel checks cover every preview, including the
lower-right child surface when using the subsurface fixture. Timing ends at a
complete Qt frame swap, not physical display presentation.
`--warm` also measures each retained composition reopening. Results include
per-CPU frequency readings before and after each cold sample; these are
observations, not a controlled clock-frequency setting.

`bash experiments/sized-capture/validate.sh HYPRLAND QUICKSHELL OUTPUT_DIRECTORY`
runs the functional matrix, including oversized sources on a rotated output and
both directions of compatibility with the installed executables.

## Validation, 2026-09-18

The 11 functional cases in [the recorded results](results/2026-09-18-validation.json)
pass. They cover simultaneous native and scaled captures on one connection,
aspect fitting and single-axis bounds, 1×1 and oversized requests, in-flight size
changes, cancellation, source closure, production sizing, odd dimensions,
fractional scaling and rotation, subsurfaces, and both compatibility directions.
DMA-BUF tracing confirms allocation and import of actual 320×180 buffers.

Transparency checks first capture an opaque source, then make its upper-right
quadrant transparent and reuse native and thumbnail buffers. Pixel checks
confirm the previous green content is cleared, including beyond the monitor's
dimensions. These pass with DMA-BUF and forced shared memory; other consumers
retain their previous images throughout the update. No content-ready signal
drops during capture-size changes.

The repository suite passes all 255 checks. Quickshell's upstream suite passes
8 of 9 test executables with Qt 6.11.2. `popupwindow::moveWithParent` fails its
position assertion with both the offscreen and minimal Qt platforms (actual x
12, expected 20); this test does not link the modified screencopy code. This
unresolved upstream-suite failure is not counted as a passing test. Release
builds of both Hyprland and Quickshell succeed, and the patches apply cleanly to
their pinned source revisions.

## Final performance measurements, 2026-09-18

The finished patch was measured with 32 and 64 synthetic 2560×1440 windows,
native captures versus 320×180 captures, and the production texture-readiness
gate. All 20 CPUs reported approximately 400 MHz before and after every sample
(399.070–401.486 MHz across recorded readings). No CPU or power settings were
changed. This records the machine's observed throttled state; it does not lock
frequency or prove its value continuously between samples.

| Windows | Native capture: first complete frame | 320×180 capture: first complete frame | Reduction |
| --- | ---: | ---: | ---: |
| 32 | 664 ms | 261 ms | 61% |
| 64 | 1,235.5 ms | 506 ms | 59% |

These are medians, excluding run 0 in each six-run group as process warmup.
The 32-window comparison has five measured samples per size. The 64-window
comparison combines ten per size across opposite capture-size orders.
[Forward-order results](results/2026-09-18-main.json) and
[reverse-order results](results/2026-09-18-reverse.json) retain all 36 cold
samples, their corresponding retained reopenings, CPU times, and frequencies.
The desktop remained active, so individual timings vary; 64-window cold ranges
were 1,087–1,463 ms native and 390–678 ms at thumbnail size.

Every cold opening had zero missing previews at reveal. Every retained reopening
had 0 ms capture preparation; its median Qt frame-swap callback was 6–7 ms for
32 windows and 11.5 ms for 64 windows. This is an isolated single-output capture
harness, not a physical Super+D-to-display measurement of the complete shell.

For 64 windows, median Quickshell CPU time fell from 1,260 to 540 ms (process-wide,
10 ms accounting granularity). One exported buffer per source totals 900 MiB at
native size versus 14.06 MiB at thumbnail size, a 64× pixel reduction. This does
not include source application buffers, double buffering, or Qt textures and
is not a total-GPU-memory measurement.

Cold opening is still visibly delayed at this clock speed. The zero-latency
target remains unmet; retaining completed previews removes capture preparation
from reopening, while this feature reduces the cost of genuinely new captures.

## Before shipping

Agree on the protocol upstream, review the renderer changes, and extend coverage
to other GPUs, cursor rendering, popups, XWayland, and enforced permission flows.
Then package matching released dependencies and exercise the real overview on
multiple outputs. Slow-CPU measurements remain required: this draft does not
establish zero latency or the 400 MHz product target.
