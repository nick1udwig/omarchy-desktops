#!/usr/bin/env bash
set -euo pipefail
experiment_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source_dir=${1:-/tmp/omarchy-scaled-capture-Hyprland}
revision=efb50993780079460b0cbed1363e2166a2de1d9f

if [[ ! -e "$source_dir" ]]; then
  git clone --depth 1 --branch v0.56.2 --recurse-submodules --shallow-submodules \
    https://github.com/hyprwm/Hyprland.git "$source_dir"
fi
[[ $(git -C "$source_dir" rev-parse HEAD) == "$revision" ]] || {
  echo "Expected Hyprland v0.56.2 at $revision" >&2
  exit 1
}
patch="$experiment_dir/hyprland-v0.56.2.patch"
if git -C "$source_dir" apply --reverse --check "$patch" 2>/dev/null; then
  echo "Prototype patch already applied"
else
  git -C "$source_dir" apply --check "$patch"
  git -C "$source_dir" apply "$patch"
fi
cmake -S "$source_dir" -B "$source_dir/build" -DCMAKE_BUILD_TYPE=Release -DNO_HYPRPM=ON
nice -n 10 cmake --build "$source_dir/build" --target Hyprland -j "${BUILD_JOBS:-4}"
echo "Built experiment: $source_dir/build/Hyprland (not installed)"
