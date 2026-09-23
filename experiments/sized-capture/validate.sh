#!/usr/bin/env bash
set -euo pipefail
experiment_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
hyprland=${1:?Usage: validate.sh HYPRLAND QUICKSHELL OUTPUT_DIRECTORY}
quickshell=${2:?Quickshell executable required}
output=${3:?Results directory required}
mkdir -p "$output"
run() {
  local name=$1
  shift
  python3 "$experiment_dir/../scaled-capture/run.py" \
    --binary "$hyprland" --quickshell "$quickshell" \
    --output "$output/$name" "$@"
}
run api --api --divisors 1 --windows 1
run api-shm --api --shm --divisors 1 --windows 1
run production --production-size --divisors 1 --windows 32 --runs 2
run fractional --production-size --divisors 1 --windows 1 --runs 2 --scale 1.6 --transform 1
run fractional-api --api --divisors 1 --windows 1 --scale 1.6 --transform 1
run alpha --api --transparent --divisors 1 --windows 1 --scale 1.6 --transform 1
run alpha-shm --api --transparent --shm --divisors 1 --windows 1 --scale 1.6 --transform 1
run odd --per-request --divisors 8 --windows 1 --runs 2 --width 1279 --height 719
run subsurface --per-request --divisors 8 --windows 1 --runs 2 --subsurface --trace

# Both directions of compatibility, in separate disposable compositors.
python3 "$experiment_dir/../scaled-capture/run.py" --binary /usr/bin/Hyprland \
  --quickshell "$quickshell" --api --legacy-server --divisors 1 --windows 1 \
  --output "$output/legacy-server"
python3 "$experiment_dir/../scaled-capture/run.py" --binary "$hyprland" \
  --quickshell /usr/bin/qs --divisors 1 --windows 1 --runs 1 \
  --output "$output/legacy-client"
