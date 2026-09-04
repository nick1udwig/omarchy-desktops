# Lifecycle verification

Verified on 2026-09-04 in the installed Omarchy session with Hyprland 0.56.2 and three monitors, including a scaled laptop display and a rotated external display. The session continued to use `/usr/share/omarchy`; neither the installed Omarchy files nor the Omarchy source checkout was changed.

## Installation and removal: passed

1. Backed up the active Hyprland configuration, shell configuration, and session desktop state. Disabled the Lua controller while its file was still present, then removed its loader block, restored the stock workspace widget, and removed the development symlink through `omarchy plugin remove`.
2. Checked the pre-feature baseline: the Hyprland configuration matched the original pre-feature backup byte-for-byte, `o.desktops` was absent, the public desktop snapshot was absent, the stock workspace bindings and widget were restored, and the source checkout was intact.
3. Created a temporary local Git snapshot of the standalone checkout and installed it using the real `omarchy plugin add <repository> --yes --enable` flow. Enabled the desktop widget, disabled the stock workspace widget, restored the explicit Lua loader, reloaded Hyprland, and restarted the shell. Verified a physical Git clone was installed, the overview had live window previews, and the original desktop-switching shortcuts worked across all three monitors.
4. Performed the documented uninstall again, this time removing the manager-installed clone. Checked that both the Hyprland configuration and normalized shell configuration exactly matched the baseline from step 2, the plugin was absent from disk and the registry, and the session assignments were retained without a public live snapshot. The source checkout was untouched.
5. Updated the temporary Git fixture with the requested shortcuts and keybinding-inspector compatibility fix, then repeated the real plugin-manager installation and explicit Lua setup. Verified the installed controller matched the source checkout, all five new bindings were registered with the intended modifier masks, `hyprctl configerrors` was empty, and `omarchy menu keybindings --print` completed and listed the new shortcuts.

No user-repository commits or remote publishing were performed. This exercises installation from a local Git repository, not downloading a published remote. The separate Lua setup and teardown steps remain required; the shell plugin manager does not run them automatically.

## Automated verification: passed

`./test/run` passes the controller, shortcut callbacks, JavaScript model, packaging, and keybinding-inspection regression tests. The inspection regression fails against the original controller and passes with the guard, including the disabled-controller case. Bash syntax checks, Lua parsing, and `omarchy plugin validate` also pass.

## Final live shortcut verification: pending unlock

The session locked automatically before the final physical-keypress tests of the new shortcuts. The test stopped before moving a window when its disposable terminal could not receive focus. The lock was not bypassed or restarted. Recheck opening the manager, switching desktops in both directions, and bringing a disposable window in both directions after normal user authentication; inspect a screenshot and short transition recording before marking these checks complete.
