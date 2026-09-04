# Desktop collections

Desktop collections are an opt-in Omarchy plugin implemented with Hyprland's Lua API and the existing Quickshell process. There is no Hyprland binary plugin or separate desktop daemon. The end-user controls are documented in [the README](../README.md#usage).

## Ownership

`hypr/desktops.lua` is the sole owner of desktop membership and selection. The user's Hyprland configuration explicitly loads it after the standard Omarchy workspace bindings, with `omarchy_desktops = { enabled = true }` set before loading the controller. `bindings = false` suppresses the feature's bindings; `omarchy_default_bindings = false` also suppresses them. Personal bindings loaded afterwards can override them.

Omarchy's keybinding inspector also evaluates that configuration, using callable no-op tables instead of the compositor API. The controller registers its bindings in that environment without querying monitors, subscribing to events, or accessing session state.

Each desktop contains an output-name-to-workspace-slots mapping. Slots have stable native numeric Hyprland workspace IDs and a remembered selection. Existing workspaces are adopted; newly allocated IDs start above 10000 and skip both existing and reserved IDs. Each output starts with ten slots. External workspaces can add more slots. Local workspace numbers in the UI are deliberately different from the global IDs exposed by Hyprland IPC and workspace rules.

Switching desktop saves the currently visible selections, visits each output's selected workspace, then restores the intended focused output. A transaction guard suppresses reactions to the controller's own intermediate workspace events. This coordinates native dispatchers; it is not a compositor-level atomic transition or a custom cross-monitor animation.

Window moves use explicit validated window addresses and silent native movement, with a workspace rule pinning the destination to its output. A follow operation then switches all outputs and focuses the window. Closed windows and disconnected destinations fail rather than falling back to an unrelated active window or output. Pinned windows are rejected, and special workspaces are outside desktop ownership.

External activation of an owned workspace switches its whole desktop. Unowned workspaces reached by activation, window creation, or silent window movement join the current desktop. Native workspace-to-monitor moves transfer ownership into the destination output's slots within the same desktop. When an output disappears, its existing workspaces are assigned to uncreated slots on a remaining output, or appended when necessary, within the same desktop. Window contents are never merged or closed. A completely headless interval defers recovery. Reconnection creates new groups rather than trying to undo recovery.

## State and UI

The controller writes two atomic snapshots under `$XDG_RUNTIME_DIR`, keyed by `$HYPRLAND_INSTANCE_SIGNATURE`:

- `omarchy-desktops-<instance>.lua`: controller state, reloaded in an empty Lua environment after a configuration reload.
- `omarchy-desktops-<instance>.json`: public UI state, including desktop names, output geometry, native workspace IDs, and selection. It does not contain window titles, addresses, or captured images.

The state is deliberately session-local. Logout/reboot starts new collections, and reusing numeric IDs in a later compositor session must not restore stale membership. Disabling removes the public snapshot but retains assignments for re-enabling within the same session. It does not renumber or close native workspaces.

`DesktopState.qml` watches the JSON file and compositor events. It serializes UI requests through `hyprctl eval` to `o.desktops`, escaping strings as Lua literals. It owns no independent membership state. The third-party `nick.desktops` plugin supplies the overview and `DesktopBar.qml`. Its bar widget replaces the stock workspace widget through the user's shell configuration, not a modification to Omarchy's built-in widget. The shell plugin and Lua controller retain separate enable/disable steps; this extraction does not add installation hooks or change their lifecycle.

`Overview.qml` opens one full-screen layer on the focused output and shows all outputs in columns within each desktop row. The host output stays fixed until the overview is reopened. Workspace tiles obtain live window captures from Quickshell's `ScreencopyView`, including inactive workspaces, and use IPC geometry normalized for output scaling and rotation. Capture stops when the overview is closed or a row leaves the viewport; an active drag is retained while scrolling. Qt sequence wrappers need normalization before accessing IPC position and size as arrays.

The `desktops-overview` IPC target exposes `status`, `geometry`, and `close` for diagnostics. Geometry is in compositor logical coordinates and includes preview availability and the window's last IPC data; it is not persisted. Desktop mutation is through the Lua controller, not through this diagnostics target.

## Verification

`bash test/desktops-test.sh` exercises real controller code with a fake Hyprland API, including multi-output selection restore, silent and following moves, stale targets, external workspaces, reload, hotplug recovery, headless intervals, disabled bindings, and snapshot lifecycle. Its Node tests cover Lua quoting, Qt IPC sequences, tile selection, and scaled/rotated preview geometry.

`bash test/inspection-test.sh` reproduces the keybinding inspector's mock API and verifies that all bindings remain discoverable without compositor initialization or session-state I/O, including when the controller is disabled.

Run `./test/run` for the standalone tests and `omarchy plugin validate` against the physical checkout for shell manifest validation. Live verification must additionally exercise desktop switching, clicking inactive previews, dragging a disposable window between outputs and desktops, cancellation, and keyboard selection. Inspect full-screen screenshots with `omarchy capture screenshot fullscreen save` and a short recording with `omarchy screenrecord --fullscreen` / `omarchy screenrecord --stop-recording`. Do not move or close unrelated user windows, or physically disconnect active monitors merely to exercise recovery.
