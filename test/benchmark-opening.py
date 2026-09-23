#!/usr/bin/env python3
"""Opt-in live benchmark: opens/closes the overview in an unlocked session.

Measures dispatch-to-first-complete Qt frame swap (not physical scanout).
Use --mode exec for the old helper-process route, or --mode global for the
native shortcut. Produces JSON; no private window titles or screenshots.
"""
import argparse
import json
import os
import socket
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--mode", choices=("exec", "global", "both"), default="global")
parser.add_argument("--runs", type=int, default=5)
args = parser.parse_args()
base = ["qs", "ipc", "-n", "-p", os.environ["OMARCHY_PATH"] + "/shell", "call", "--"]


def call(*command):
    return subprocess.check_output(base + list(command), text=True, timeout=10)


def status():
    return json.loads(call("desktops-overview", "status"))


lock = ["qs", "ipc", "-n", "-p", os.environ["OMARCHY_PATH"] + "/shell/lock.qml", "call", "--", "lock", "isLocked"]
assert subprocess.check_output(lock, text=True, timeout=10).strip() == "false", "Unlock the session first"
assert not status()["opened"], "Close the overview before benchmarking"
sockpath = os.path.join(os.environ["XDG_RUNTIME_DIR"], "hypr", os.environ["HYPRLAND_INSTANCE_SIGNATURE"], ".socket.sock")
commands = {
    "global": '/dispatch hl.dsp.global("omarchy-desktops:toggle")',
    "exec": '/dispatch hl.dsp.exec_cmd("omarchy-shell shell toggle nick1udwig.desktops")',
}
modes = ("exec", "global") if args.mode == "both" else (args.mode,)
for run in range(args.runs * len(modes)):
    mode = modes[run % len(modes)]
    time.sleep(0.4)
    before = status()
    assert not before["opened"], "Overview was opened during the benchmark"
    try:
        with socket.socket(socket.AF_UNIX) as client:
            client.settimeout(5)
            client.connect(sockpath)
            sent = time.time_ns() / 1_000_000
            client.sendall(commands[mode].encode())
            reply = client.recv(4096).decode().strip()
            assert reply == "ok", reply
        # Avoid hammering the UI thread with status requests during rendering.
        time.sleep(0.35)
        deadline = time.monotonic() + 8
        while True:
            current = status()
            frames = [output["firstFrameAt"] for output in current["outputs"]]
            if current["opened"] and frames and all(frames):
                break
            assert time.monotonic() < deadline, "No complete frame: check unlocked/awake outputs"
            time.sleep(0.1)
        assert current["captures"]["missingAtReveal"] == 0
        print(json.dumps({
            "run": run, "mode": mode, "desktop": current["desktop"],
            "dispatch_to_open_ms": round(current["openedAt"] - sent, 2),
            "open_work_ms": current["openWorkMs"],
            "first_output_ms": round(min(frames) - sent, 2),
            "all_outputs_ms": round(max(frames) - sent, 2),
            "preparation_ms": current["captures"]["preparationMs"],
            "capture_requests": current["captures"]["requests"] - before["captures"]["requests"],
            "requests_before_first_frame": max(output.get("firstFrameRequests", before["captures"]["requests"])
                for output in current["outputs"]) - before["captures"]["requests"],
            "views": current["captures"]["views"],
            "missing_at_reveal": current["captures"]["missingAtReveal"],
        }), flush=True)
    finally:
        call("desktops-overview", "close")
