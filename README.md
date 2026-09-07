# Omarchy Desktops

Virtual desktops with an Exposé-style overview for Omarchy.
Each desktop has independent workspaces on every monitor; switching desktops switches all monitors together.
Based in part on [omarchy-expose](https://github.com/kristofferR/omarchy-expose).



[![Demo](https://github.com/user-attachments/assets/36b6eca6-5e97-4112-acc1-24157550e7ee)](https://github.com/user-attachments/assets/36b6eca6-5e97-4112-acc1-24157550e7ee)



## Installation

Run these commands from this checkout, with no existing `nick1udwig.desktops` installation:

```bash
omarchy plugin validate "$PWD"
mkdir -p "$HOME/.config/omarchy/plugins"
ln -s "$PWD" "$HOME/.config/omarchy/plugins/nick1udwig.desktops"
omarchy-shell shell rescanPlugins
omarchy plugin enable nick1udwig.desktops --section left --after omarchy.menu
omarchy plugin disable omarchy.workspaces
```

Keep the checkout in place while the plugin is installed.
Back up `~/.config/hypr/hyprland.lua`, then add this block after Omarchy's defaults and before any personal keybinding overrides:

```lua
omarchy_desktops = { enabled = true }
dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/nick1udwig.desktops/hypr/desktops.lua")
```

Both the shell plugin and this configuration block are required.
Apply the changes:

```bash
hyprctl reload
hyprctl configerrors
omarchy restart shell
```

## Usage

Your existing workspaces become Desktop 1 without moving their windows.
The bar shows the current desktop and each monitor's local workspaces.

| Shortcut | Action |
| --- | --- |
| `Super + D` | Toggle the overview |
| `Ctrl + Super + Up / Down` | Previous / next desktop; moving past the last creates one |
| `Ctrl + Shift + Super + Up / Down` | Move the focused window to the previous / next desktop and follow it |
| `Super + 1–9 / 0` | Workspace 1–10 on the focused monitor |
| `Super + Shift + 1–9 / 0` | Move a window to that workspace and follow it |
| `Super + Shift + Alt + 1–9 / 0` | Send a window to that workspace without following |

The overview opens on every monitor, showing windows from that monitor's selected workspace and a sidebar of desktop previews.
Click a desktop preview to switch desktops, or a window to focus it and close the overview.
Drag a window onto another monitor's window area to move it there, or onto a desktop preview to send it there without following.
Hold a drag near the sidebar's top or bottom edge to scroll, or press `Esc` to cancel it.
Double-click a desktop's name to rename it; click **New desktop** or press `Ctrl + N` to create one.

Type in the filter to search by window title or application across the displayed workspaces.
Use arrow keys to select a window, `Enter` to activate it, and `Space` to toggle an enlarged preview when the filter is empty.
Use `Tab / Shift + Tab` to transfer keyboard control between monitors.
Press `Esc` to restore a preview, clear the filter, or close the overview.

Empty desktops are removed when you leave them, and remaining desktops are renumbered.
Desktop assignments and names survive configuration reloads and shell restarts, but reset on logout or reboot.
Disconnected monitors' workspaces transfer to another monitor and return when reconnected.
Scratchpads and pinned windows remain global; unpin a window before moving it between desktops.

## Configuration

The overview follows your Omarchy theme and Hyprland corner rounding.
Set `bindings = false` in `omarchy_desktops` to supply your own keybindings.
Setting `omarchy_default_bindings = false` also suppresses the plugin's bindings.

## Disabling or removing

Disabling the shell plugin alone does not unload the desktop controller.

1. Set `omarchy_desktops = { enabled = false }` in your Hyprland configuration, keeping the `dofile(...)` line.
2. Run `hyprctl reload` and check `hyprctl configerrors`.
3. If uninstalling, remove both configuration lines, then reload and check again.
4. Restore the normal workspace widget:

   ```bash
   omarchy plugin disable nick1udwig.desktops
   omarchy plugin enable omarchy.workspaces --section left --after omarchy.menu
   omarchy restart shell
   ```

5. If uninstalling, run `omarchy plugin remove nick1udwig.desktops` to remove the installation symlink.

Your windows and underlying workspace numbers are preserved.
Re-enabling within the same session restores saved desktop assignments.

## Further reading

See [Architecture](docs/architecture.md) and [Performance](docs/performance.md) for implementation details.

## License

[MIT](LICENSE), with retained Omarchy and [Exposé license notices](vendor/expose/LICENSE).
See [Exposé provenance](vendor/expose/UPSTREAM.md) for upstream credits and local adaptations.
