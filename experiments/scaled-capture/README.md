# Compositor-side scaled capture experiment

This is an isolated feasibility prototype for Hyprland **v0.56.2**, commit
`efb50993780079460b0cbed1363e2166a2de1d9f`. It does not change the installed
compositor, desktop configuration, Quickshell, or the production overview.

The patch makes `OMARCHY_CAPTURE_DIVISOR=2`, `4`, or `8` advertise smaller window
capture buffers. Missing/unrecognized values use native dimensions. Positive
dimensions round upwards. Hyprland renders directly into the smaller capture
buffer using the whole window's projection; pixel clipping is scaled into the
destination buffer as well. Application window buffers remain full resolution.
Monitor and region capture sizes remain unchanged.

The setting affects **every window capture in that compositor process**. This
is a benchmark mechanism, not a production configuration option. Do not install
this binary or replace the running desktop with it. Shipping this would require
per-client size negotiation, source/consumer lifetime handling, and broader
compositor regression coverage.

## Reproduce

With Hyprland's build dependencies, Quickshell, Python 3, and FFmpeg installed:

```sh
bash experiments/scaled-capture/build.sh
python3 experiments/scaled-capture/run.py \
  --binary /tmp/omarchy-scaled-capture-Hyprland/build/Hyprland \
  --output /tmp/capture-benchmark \
  --divisors 1 2 4 8 --windows 1 32 64 --runs 6
```

The runner starts disposable nested compositors, each with a private runtime
directory and IPC socket. It creates a 2560×1440 headless output, removes the
nested backend's visible output, and opens synthetic fixed-size windows there.
It never sends IPC to the user's compositor. Startup can briefly show the nested
backend window. Child processes are terminated on success or failure; logs and
synthetic images are retained under the output directory.

The client uses copies of the repository's actual `WindowCapture`, `CaptureCache`,
`CapturedPreview`, and `CaptureScheduler` components. Every sample destroys and
recreates capture producers, while keeping the synthetic source windows and
client process alive. **These are cold capture samples, not retained-cache
openings.** Report the first sample separately from subsequent samples because
Qt/GPU initialization can affect it.

The reveal still waits for every shared preview texture to render. Each sample
asserts zero missing previews and checks every native capture's dimensions. The
first sample at each size/window count saves an image and checks all four
quadrants of every preview, detecting cropping, inversion, missing content, and
incorrect layout. Timing ends at the first complete Qt frame swap; this is not
physical keypress-to-scanout latency or a full three-monitor overview benchmark.

`--scale`, `--transform`, `--width`, and `--height` allow additional geometry
checks. `--subsurface --windows 1` builds a small Wayland client with an offset
cyan child surface, to test clipping beyond the reduced buffer's original bounds.
This option additionally requires a C compiler and `wayland-scanner`.
`--shm` forces Quickshell's shared-memory fallback; `--trace` enables
buffer/compositor logging to identify the capture path. Keep traced runs out of
performance comparisons. CPU values are coarse `/proc` process-time deltas;
buffer bytes are calculated single-buffer payload sizes, not measured total GPU
memory. None of these runs emulate a 400 MHz processor.

## Results, 2026-09-18

Framework Laptop 13, i7-1280P / Intel GPU, Quickshell 0.3.1, Qt 6.11.2,
Hyprland 0.56.2 built with GCC 16.2.1 in Release mode. One headless 2560×1440
output at 60 Hz, static synthetic windows of that same size, 320×180 previews.
The normal desktop continued running, so results include background-load noise.

Each case ran six cold-capture samples. Tables exclude the first sample's
process/GPU warmup and use the following five samples. The 64-window comparison
was repeated in reverse divisor order to check warmup/order effects.

| Export buffer size | 32 windows, median complete frame | 64 windows, forward order | 64 windows, reverse order | 64 windows, combined median |
| --- | ---: | ---: | ---: | ---: |
| 2560×1440 | 147 ms | 292 ms | 220 ms | 236.5 ms |
| 1280×720 | 73 ms | 117 ms | 119 ms | 118 ms |
| 640×360 | 59 ms | 105 ms | 96 ms | 101 ms |
| 320×180 | 51 ms | 87 ms | 97 ms | 96.5 ms |

For 64 windows, the combined median falls **59% (2.45× faster)**. The combined
median preparation barrier falls from 224.5 ms to 84 ms. Coarse Quickshell CPU
time over the measurement interval falls from 225 ms to 50 ms; these counters
have 10 ms resolution and include status calls. A single-window case remains
around 40–50 ms: frame scheduling and fixed client work dominate that case.

Single-buffer payload for 64 windows falls from **900 MiB to 14.06 MiB (64×)**.
This is calculated RGBA pixel storage, excluding stride/modifier overhead,
double buffering, source application buffers, and Qt/compositor allocations.
It is not a measurement of total system or GPU memory savings.

All **96 performance samples** had zero missing previews at reveal; image
checks covered every preview in the first sample of each of the 16 cases.
An additional **31 validation samples** checked native dimensions and readiness:

- Odd 1279×719 window dimensions, divisors 1/2/4/8.
- 1.6× monitor scaling with 90° rotation, divisors 1/2/4/8.
- Forced SHM capture, divisors 1/4/8.
- A separate lower-right subsurface, divisors 1/2/4/8.
- A traced GPU capture confirmed creation and Qt import of a **640×360 DMA-BUF**
  using the Intel render node, with no full-size capture buffer in that request.

The original 2560×1440 application textures still exist. The avoided work is
the additional native-size export and its allocation/import/downscaling cost.

Raw samples: [forward order](results/2026-09-18-main.csv),
[reverse order](results/2026-09-18-reverse.csv),
[validation summary](results/2026-09-18-validation.json).
First-process samples are retained in the CSVs as `run=0`, not discarded from
the evidence. All subsequent samples also recreate their capture buffers.
The 64-window first-process samples were 499/243 ms at native size and 139/130 ms
at 320×180 (forward/reverse order).

The repository regression suite passed **251 checks**, patch applicability was
verified against the pinned revision, and all disposable test processes exited.

## Before production integration

- Negotiate a per-client maximum physical pixel size instead of a global divisor.
  Preserve full resolution for ordinary screenshots/recording and choose enough
  pixels for the largest preview consumer, including HiDPI and Quick Look.
- Test live resizing, monitor moves, popups, cursor overlays, transparency,
  color management/HDR, permission-denied content, and other GPU drivers.
- Keep capture buffer dimensions separate from source geometry and damage;
  retain the rendered-texture readiness barrier during size changes.
- Profile remaining delegate construction, allocations, imports, and the
  32-capture startup batches. Smaller buffers do not remove those costs.
- Validate the full overview on genuinely slow hardware. This experiment
  establishes a useful capture optimization, not zero latency at 400 MHz.
