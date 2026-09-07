#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

if ! command -v qs >/dev/null; then
  echo 'skip - Quickshell capture cache integration (qs is not installed)'
  exit 0
fi
capture_test_dir=$(mktemp -d)
trap 'rm -rf "$capture_test_dir"' EXIT
mkdir -p "$capture_test_dir/vendor/expose" "$capture_test_dir/runtime"
chmod 700 "$capture_test_dir/runtime"
cp "$ROOT/test/capture-cache.qml" "$capture_test_dir/shell.qml"
cp "$ROOT/"{CaptureCache.qml,CaptureScheduler.qml,CaptureScheduler.js,WindowCapture.qml} "$capture_test_dir/"
cp "$ROOT/vendor/expose/WindowModel.js" "$capture_test_dir/vendor/expose/"
# No compositor connection, windows, or source buffers are needed to check
# ownership, refresh demand, fallback lifetime, and deferred destruction.
if ! env -u WAYLAND_DISPLAY -u DISPLAY QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=basic \
    XDG_RUNTIME_DIR="$capture_test_dir/runtime" timeout 5 qs -p "$capture_test_dir" >"$capture_test_dir/log" 2>&1; then
  cat "$capture_test_dir/log" >&2
  fail 'capture cache integration'
fi
if rg -q 'not ok -' "$capture_test_dir/log" || ! rg -q 'ok - the last consumer releases' "$capture_test_dir/log"; then
  cat "$capture_test_dir/log" >&2
  fail 'capture cache integration'
fi
sed -n 's/^.*qml: \(ok - .*\)$/\1/p' "$capture_test_dir/log"
