# Exposé components

Source: [kristofferR/omarchy-expose](https://github.com/kristofferR/omarchy-expose), commit `7a31c5e846a2e12bc1353ba5a0d90d42cc4f2dc8` (version 4.1.0). These files are vendored so the desktop plugin does not require a second plugin installation or a network connection at runtime.

`WindowModel.js` and `IconResolver.js` are unchanged upstream files. `WindowCard.qml` retains the floating caption presentation and geometry transitions; pointer handling lives in `ExposeCard.qml`. Unused footer modes, loaders, settings hooks, and the duplicated mouse handler are removed. The card uses the desktop plugin's `CapturedPreview.qml`, shared capture scheduler, and `PreviewClip.qml`. It displays the exported texture directly without the upstream doubled-size intermediate layer. Preview corners follow `Style.cornerRadius` without a minimum; borders use Omarchy's surface/active-border specifications, including gradients and per-side widths.

`Layout.js` adapts composition and centered Quick Look geometry from upstream `Overview.qml`, with explicit dependencies and arguments. Its ratio-only entry point avoids recomposition on title-only metadata changes. The original row assignment and alignment rules remain; scale is solved from row width and total height limits instead of a 12-step binary search. Natural dimensions are calculated and sorted once, and only the winning layout allocates positioned rectangles. The unused in-place Quick Look mode is omitted.

The surrounding per-monitor surfaces, desktop sidebar, synchronized filter, desktop-controller integration, and drag-and-drop adapter are implemented by Omarchy Desktops. Upstream's single-display overlay, hot corners, settings UI, activation script, and compositor-wide blur helper are not installed or run.

Copyright (c) 2026 Harel Malka and kristofferR. Distributed under the MIT license in [LICENSE](LICENSE).
