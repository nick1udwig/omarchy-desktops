# Per-monitor Exposé verification

Verified live on 2026-09-04 with the development checkout linked as `nick.desktops`, using the installed Omarchy shell and Hyprland 0.56.2. The layout included a 1.6× scaled laptop display, a landscape external monitor, and a rotated portrait monitor.

## Passed checks

- Opening with Super+D mounted three monitor-local Exposé surfaces, three filters, and six desktop thumbnails for the two existing desktops. All eight existing window cards reported live capture content.
- Screenshots were inspected on all three monitors. Each sidebar showed that monitor's own selected workspace for each desktop; the main window composition remained inside its content area without overlap or stretched previews.
- Typing a shared filter produced the expected results independently on each monitor. A query for the disposable test window matched only its own monitor; an unmatched query left all three grids empty. Escape cleared the filter without dismissing the manager.
- Space entered Quick Look, Escape restored the composition, and Tab transferred keyboard control to another monitor.
- Silently moving the disposable test window to an inactive local workspace removed it from Exposé. Selecting that workspace made it appear again, proving the grid is scoped to the selected workspace rather than the whole desktop.
- Dragging the disposable window to Desktop 2's thumbnail sent it to Desktop 2's selected workspace 2, not hardcoded workspace 1. The monitor stayed the same and Desktop 1 remained active.
- Escape during an in-progress drag canceled it without moving the test window or closing Exposé.
- Clicking Desktop 2 in the sidebar switched every monitor's selected workspace together while keeping all Exposé surfaces open.
- Clicking the test window focused that exact window and closed Exposé on every monitor. No unrelated windows changed workspace or monitor.
- All five global desktop shortcuts passed live checks. Original desktop and workspace selections were restored and disposable windows were closed afterwards.

Full-screen recordings of the shortcut transitions and drag-and-drop flow were captured locally and inspected; private desktop captures are not included in the repository. `hyprctl configerrors` was empty. The shell log contained no runtime errors from the desktop plugin; unrelated stock multi-monitor IPC warnings were not changed.

`./test/run` passes the controller, shortcut callback, keybinding-inspection, workspace-scoping, search, layout, icon identity, and packaging tests. The upstream Exposé model/icon Qt tests also passed all 17 checks. Manifest validation and `git diff --check` pass. No Omarchy source changes or additional packages were needed.

## Theme integration pass

Verified later on 2026-09-04 with Tokyo Night and the user's `decoration:rounding = 0`. The sidebar, desktop selection, search control, and window previews now use Omarchy's menu palette, shared corner setting, and border specifications. Floating captions and roomier composition follow the upstream Exposé presentation. Portrait workspace thumbnails retain the output's aspect ratio.

- Inspected square-corner screenshots on the landscape, portrait, and scaled laptop displays; checked theme colors, readable captions, preview proportions, and unclipped controls.
- Temporarily set runtime rounding to 18 and confirmed all three rails, filters, and Exposé preview frames updated. Workspace thumbnail corners use the inset radius of 12. Inspected the actual rounded captures, including sidebar contents; an initial mask-texture dependency issue found during this check was corrected by placing the mask beside the content layer.
- Applied the stock Catppuccin Latte palette through shell IPC without changing theme files. An already-open overview updated to its light background, dark text, and blue selection color. Inspected the light-palette screenshot and a short full-screen recording of the rounded/light/restored states.
- Restored the original Tokyo Night shell palette and rounding 0. No user theme files or Hyprland configuration files were edited by the tests.
- Re-ran the disposable-window interaction checks after the styling changes: selected-workspace scoping, drag cancellation, silent drop to the destination's selected workspace, coordinated desktop switching, filtering, and window activation all passed. No unrelated windows moved; original selections were restored and the disposable window was closed.

The standalone suite now also checks corner settings 0, 2, 8, 16, and 24, theme-token usage, border-spec integration, and avoiding offscreen masks for square previews. Tests, manifest validation, and whitespace checks pass. Captures remain local and are not shipped in the plugin.
