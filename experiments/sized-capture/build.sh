#!/usr/bin/env bash
# Build a matched draft protocol/server/client locally. Never install them.
set -euo pipefail
patch_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
build_root=${1:-/tmp/omarchy-sized-capture}
mkdir -p "$build_root"
build_root=$(cd -- "$build_root" && pwd)

clone() {
  local url=$1 tag=$2 revision=$3 destination=$4
  if [[ ! -e "$destination" ]]; then
    git clone --depth 1 --branch "$tag" --recurse-submodules --shallow-submodules "$url" "$destination"
  fi
  [[ $(git -C "$destination" rev-parse HEAD) == "$revision" ]] || {
    echo "Unexpected revision in $destination; expected $revision" >&2
    exit 1
  }
}
apply() {
  local destination=$1 patch=$2
  if ! git -C "$destination" apply --reverse --check "$patch" 2>/dev/null; then
    git -C "$destination" apply --check "$patch"
    git -C "$destination" apply "$patch"
  fi
}

clone https://github.com/hyprwm/Hyprland.git v0.56.2 efb50993780079460b0cbed1363e2166a2de1d9f "$build_root/Hyprland"
clone https://github.com/quickshell-mirror/quickshell.git v0.3.1 1a4716cde794a59928d9d9fc15f2afc7a95de360 "$build_root/quickshell"
protocols="$build_root/Hyprland/subprojects/hyprland-protocols"
[[ $(git -C "$protocols" rev-parse HEAD) == bd153e76f751f150a09328dbdeb5e4fab9d23622 ]]
apply "$protocols" "$patch_dir/hyprland-protocols.patch"
apply "$build_root/Hyprland" "$patch_dir/hyprland-v0.56.2.patch"
apply "$build_root/quickshell" "$patch_dir/quickshell-v0.3.1.patch"

# Build-only dependencies, isolated under this directory.
clone https://github.com/CLIUtils/CLI11.git v2.5.0 4160d259d961cd393fd8d67590a8c7d210207348 "$build_root/CLI11"
clone https://github.com/KhronosGroup/Vulkan-Headers.git v1.4.321 2cd90f9d20df57eac214c148f3aed885372ddcfe "$build_root/Vulkan-Headers"
clone https://github.com/ninja-build/ninja.git v1.13.1 79feac0f3e3bc9da9effc586cd5fea41e7550051 "$build_root/ninja"
cmake -S "$build_root/CLI11" -B "$build_root/CLI11/build" -DCLI11_BUILD_TESTS=OFF -DCLI11_BUILD_EXAMPLES=OFF -DCMAKE_INSTALL_PREFIX="$build_root/deps"
cmake --install "$build_root/CLI11/build"
cmake -S "$build_root/Vulkan-Headers" -B "$build_root/Vulkan-Headers/build" -DCMAKE_INSTALL_PREFIX="$build_root/deps"
cmake --install "$build_root/Vulkan-Headers/build"
cmake -S "$build_root/ninja" -B "$build_root/ninja/build" -DBUILD_TESTING=OFF -DCMAKE_BUILD_TYPE=Release
nice -n 10 cmake --build "$build_root/ninja/build" -j "${BUILD_JOBS:-4}"

cmake -S "$build_root/Hyprland" -B "$build_root/Hyprland/build" -DCMAKE_BUILD_TYPE=Release -DNO_HYPRPM=ON
# Hyprland's generator rule does not track XML changes. Generate this protocol
# explicitly from the patched XML, including when installed protocols exist.
hyprwayland-scanner "$protocols/protocols/hyprland-toplevel-export-v1.xml" "$build_root/Hyprland/protocols"
nice -n 10 cmake --build "$build_root/Hyprland/build" --target Hyprland -j "${BUILD_JOBS:-4}"

cmake -G Ninja -S "$build_root/quickshell" -B "$build_root/quickshell/build" \
  -DCMAKE_MAKE_PROGRAM="$build_root/ninja/build/ninja" -DCMAKE_PREFIX_PATH="$build_root/deps" \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON -DCRASH_HANDLER=OFF
nice -n 10 cmake --build "$build_root/quickshell/build" -j "${BUILD_JOBS:-4}"
echo "Built isolated draft in $build_root; nothing installed into the desktop."
