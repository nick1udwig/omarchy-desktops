# Omarchy Desktops

Desktop collections and a Mission Control-style overview for Omarchy. Each desktop has independent workspaces on every monitor; switching desktops switches all monitors together.

This is a standalone `nick.desktops` shell plugin, with a per-monitor desktop sidebar and macOS-style Exposé. It needs no Omarchy source modifications and no compiled Hyprland plugin. Its live preview cards, composition, search model, and icon resolution reuse [omarchy-expose](https://github.com/kristofferR/omarchy-expose).

## Requirements

An Omarchy session with its Lua-capable Hyprland configuration and Quickshell desktop, including the Hyprland and Wayland capture modules. The plugin uses Omarchy's existing `qs.Commons`, `qs.Ui`, and `omarchy-shell` interfaces. The controller runs inside Hyprland; the overview runs inside the existing shell process.

## Local installation

From this checkout, with no existing `nick.desktops` installation at the destination:

```bash
omarchy plugin validate "$PWD"
mkdir -p "$HOME/.config/omarchy/plugins"
ln -s "$PWD" "$HOME/.config/omarchy/plugins/nick.desktops"
omarchy-shell shell rescanPlugins
omarchy plugin enable nick.desktops --section left --after omarchy.menu
omarchy plugin disable omarchy.workspaces
```

The directory symlink is only for local development. The repository itself contains ordinary files and is suitable for distribution through `omarchy plugin add` once published. Validate the physical checkout, not its development symlink.

Back up `~/.config/hypr/hyprland.lua`, then add the following after Omarchy's defaults have loaded:

```lua
omarchy_desktops = { enabled = true }
dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/nick.desktops/hypr/desktops.lua")
```

Load any personal keybinding overrides after that block if they should take precedence. Then apply:

```bash
hyprctl reload
hyprctl configerrors
omarchy restart shell
```

The shell plugin manager does not load the Lua module automatically. Both the shell plugin and the Hyprland configuration block are required. This extraction intentionally keeps that explicit setup rather than introducing installation hooks or changing enable/disable behavior.

## Usage

Your existing workspaces become Desktop 1 without moving their windows. Each monitor gets local workspace numbers starting at 1, so `Super + 2` means workspace 2 on the focused monitor within the current desktop. The bar shows the desktop number and that monitor's local workspaces.

| Shortcut | Action |
| --- | --- |
| `Super + D` | Toggle the desktop manager / overview |
| `Ctrl + Super + Up / Down` | Previous / next desktop; moving past the last creates one |
| `Ctrl + Shift + Super + Up / Down` | Move the focused window to the previous / next desktop and follow it |
| `Super + 1–9 / 0` | Workspace 1–10 on the focused monitor |
| `Super + Shift + 1–9 / 0` | Move a window to that workspace and follow it |
| `Super + Shift + Alt + 1–9 / 0` | Send a window to that workspace without following |

The manager opens on every monitor at once. Each monitor has a left sidebar with one live thumbnail per desktop, showing that desktop's currently selected workspace on that monitor. The main Exposé area shows only windows on the current desktop's selected workspace for that monitor, not every workspace or another monitor's windows.

Previews share a capture budget of about 30 frames per second across all monitors. Window cards refresh up to five times per second, sidebar thumbnails once per second, and an enlarged Space preview targets 15 frames per second when budget is available. With many windows, each preview updates less often. Movement and selection animations run independently; dragging pauses capture while retaining the last frames.

Click a desktop thumbnail to switch all monitors together while keeping the manager open. Click a window to activate it and close the manager everywhere. Drag a window card onto a desktop thumbnail to send it to that desktop's selected workspace on the same monitor without following it. Hold a drag near a sidebar's top or bottom edge to scroll. Double-click a desktop's name to rename it. **New desktop** or `Ctrl + N` creates and selects a desktop.

Type in the top filter to search by window title or application. The filter is shared across monitors, but each grid keeps its own workspace scope. Arrow keys select windows spatially; `Space` enlarges or restores a preview when the filter is empty; `Enter` activates the selected window. `Tab / Shift + Tab` transfers keyboard control between monitors. `Esc` restores a preview, clears a nonempty filter, or closes the manager. The existing workspace-number shortcuts still select local workspaces; they are no longer represented as a grid of empty tiles in the manager.

Desktop assignments and names survive configuration reloads and shell restarts, but reset on logout or reboot. Disconnecting a monitor transfers its existing workspaces to another monitor within their original desktops; reconnecting it starts fresh workspace groups. Scratchpads and pinned windows remain global; unpin a window before moving it between desktops. Disabling does not close any windows, but their underlying workspace numbers are retained. See the removal instructions below.


## Configuration

The overview follows the active Omarchy theme, including menu colors and transparency, selection colors, border gradients/widths, font sizing, and spacing. Sidebar, controls, and Exposé previews use Hyprland's `decoration:rounding` through the shell's shared style: `0` is square, a positive value is rounded. The manager refreshes that setting when opened; no separate desktop-plugin theme configuration is needed.

`omarchy_desktops` retains the existing options:

- `enabled = true`: enable the controller.
- `bindings = false`: keep the controller but register your own bindings. Setting Omarchy's `omarchy_default_bindings = false` also suppresses the feature's bindings.
- `overview_plugin = "nick.desktops"`: override the overview target when using another plugin ID; this is now the default.

## Development and tests

Edit this checkout directly. After QML changes, run `omarchy restart shell`. After Lua changes, run `hyprctl reload` and check `hyprctl configerrors`. Keep the normal session `OMARCHY_PATH`; it still points to Omarchy, not this plugin.

Run the independent controller, keybinding-inspection, workspace-scoping, Exposé composition, capture-scheduling, JavaScript model, and packaging tests with Bash, Lua, and Node.js:

```bash
./test/run
omarchy plugin validate "$PWD"
```

The tests do not need an Omarchy source checkout or a running compositor. Manifest validation uses the installed Omarchy CLI.

For live verification, use a disposable test window, confirm coordinated monitor switching and drag-and-drop, and inspect `omarchy capture screenshot fullscreen save`. For transitions, record a short clip with `omarchy screenrecord --fullscreen` and stop it with `omarchy screenrecord --stop-recording`. Never move or close unrelated user windows as part of a test.

See [Architecture](docs/architecture.md) for controller ownership, state, and the UI boundary.
See [Performance](docs/performance.md) for the capture design and live measurements.

## Disabling or removing

Disabling only the shell plugin does not unload the Lua controller. To return to ordinary workspaces without leaving a stale controller snapshot:

1. While the Lua file is still installed, change the configuration block to `omarchy_desktops = { enabled = false }`, retaining the `dofile(...)` line. Run `hyprctl reload` and check `hyprctl configerrors`.
2. Remove the desktop configuration block if uninstalling, then reload and check again.
3. Run `omarchy plugin disable nick.desktops`, restore the normal widget with `omarchy plugin enable omarchy.workspaces --section left --after omarchy.menu`, and run `omarchy restart shell`.
4. If uninstalling, run `omarchy plugin remove nick.desktops`. For a local development symlink, this removes the link, not this checkout.

Workspace contents are not deleted or renumbered. Within the same session, re-enabling the controller restores its saved assignments.

## License

MIT; see [LICENSE](LICENSE). Omarchy's copyright notice is retained for the extracted code and test helpers. Vendored Exposé components retain Harel Malka's and kristofferR's notices in [their license](vendor/expose/LICENSE); [provenance and local adaptations](vendor/expose/UPSTREAM.md) are documented alongside the code.
