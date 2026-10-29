#!/bin/bash

set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

plugin_shell_dir="${OMARCHY_PATH:-/usr/share/omarchy}/shell"
if ! command -v qs >/dev/null || [[ ! -d $plugin_shell_dir/Commons || ! -d $plugin_shell_dir/Ui ]]; then
  echo 'skip - external plugin loading (Quickshell and Omarchy shell are required)'
  exit 0
fi

plugin_test_dir=$(mktemp -d)
trap 'rm -rf "$plugin_test_dir"' EXIT
mkdir -p "$plugin_test_dir/runtime"
chmod 700 "$plugin_test_dir/runtime"
ln -s "$plugin_shell_dir/Commons" "$plugin_test_dir/Commons"
ln -s "$plugin_shell_dir/Ui" "$plugin_test_dir/Ui"
cp "$ROOT/test/plugin-loading.qml" "$plugin_test_dir/shell.qml"
if ! env -u WAYLAND_DISPLAY -u DISPLAY QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=basic XDG_RUNTIME_DIR="$plugin_test_dir/runtime" OMARCHY_DESKTOPS_PATH="$ROOT" timeout 10 qs -p "$plugin_test_dir" >"$plugin_test_dir/log" 2>&1; then
  cat "$plugin_test_dir/log" >&2
  fail 'external plugin loading'
fi
if rg -q 'not ok -' "$plugin_test_dir/log" || ! rg -q 'ok - desktop thumbnail uses the Omarchy menu palette' "$plugin_test_dir/log"; then
  cat "$plugin_test_dir/log" >&2
  fail 'external plugin loading'
fi
sed -n 's/^.*qml: \(ok - .*\)$/\1/p' "$plugin_test_dir/log"
