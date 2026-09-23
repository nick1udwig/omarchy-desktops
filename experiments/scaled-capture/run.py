#!/usr/bin/env python3
"""Benchmark a disposable compositor; never sends IPC to the user's desktop.

Requires the patched Hyprland executable, Quickshell, and FFmpeg.
Results measure request-to-complete Qt frame swap, not physical display latency.
"""
import argparse
import json
import math
import os
from pathlib import Path
import signal
import shutil
import socket
import subprocess
import tempfile
import time

HERE = Path(__file__).resolve().parent


def wait_for(check, description, timeout=30):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = check()
        if value:
            return value
        time.sleep(0.1)
    raise RuntimeError("Timed out: " + description)


def cpu_ms(pid):
    fields = Path(f"/proc/{pid}/stat").read_text().rsplit(") ", 1)[1].split()
    return (int(fields[11]) + int(fields[12])) * 1000 / os.sysconf("SC_CLK_TCK")


def cpu_frequencies_khz():
    return [int(path.read_text()) for path in sorted(
        Path("/sys/devices/system/cpu").glob("cpu[0-9]*/cpufreq/scaling_cur_freq"))]


def verify_image(path, count, subsurface=False, transparent=False, background=(32, 32, 32), transparent_indices=None):
    dimensions = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries",
        "stream=width,height", "-of", "json", str(path)], text=True))["streams"][0]
    width, height = dimensions["width"], dimensions["height"]
    assert width * 9 == height * 16, dimensions
    pixels = subprocess.check_output(["ffmpeg", "-v", "error", "-i", str(path), "-f", "rawvideo", "-pix_fmt", "rgb24", "-"])
    colors = [(0.2, 0.2, (255, 0, 0)), (0.8, 0.2, (0, 255, 0)),
              (0.2, 0.8, (0, 0, 255)), (0.8, 0.8, (255, 255, 0))]
    if subsurface:
        colors.append((0.65, 0.65, (0, 255, 255)))
    for index in range(count):
        for x, y, expected in colors:
            if transparent and x == 0.8 and y == 0.2 and (transparent_indices is None or index in transparent_indices):
                expected = background
            px = int((index % 8 * 320 + x * 320) * width / 2560)
            py = int((index // 8 * 180 + y * 180) * height / 1440)
            offset = (py * width + px) * 3
            pixel = tuple(pixels[offset:offset + 3])
            assert max(abs(a-b) for a, b in zip(pixel, expected)) <= 12, (index, x, y, pixel, expected)


def fitted_size(native, bounds):
    width = min(native[0], bounds[0]) if bounds[0] > 0 else native[0]
    height = min(native[1], bounds[1]) if bounds[1] > 0 else native[1]
    if width * native[1] <= height * native[0]:
        height = max(1, width * native[1] // native[0])
    else:
        width = max(1, height * native[0] // native[1])
    return [width, height]


def benchmark(args, divisor, count):
    case = args.output / f"d{divisor}-n{count}"
    case.mkdir(parents=True, exist_ok=True)
    config_file = case / "hyprland.lua"
    config_file.write_text((HERE / "hyprland.lua").read_text().replace("scale = 1 }", f"scale = {args.scale}, transform = {args.transform} }}"))
    config = case / "qml"
    production = config / "production"
    (production / "vendor/expose").mkdir(parents=True, exist_ok=True)
    for name in ("Capture.qml", "Sources.qml"):
        shutil.copyfile(HERE / name, config / name)
    for name in ("CaptureScheduler.qml", "CaptureScheduler.js", "CaptureCache.qml", "WindowCapture.qml", "CapturedPreview.qml"):
        shutil.copyfile(HERE.parent.parent / name, production / name)
    shutil.copyfile(HERE.parent.parent / "vendor/expose/WindowModel.js", production / "vendor/expose/WindowModel.js")
    native = [math.floor(dimension * args.scale + 0.5) for dimension in (args.width, args.height)]
    bounds = [math.ceil(d / divisor) for d in native] if divisor > 1 else [0, 0]
    if args.per_request:
        capture = production / "WindowCapture.qml"
        capture.write_text(capture.read_text().replace("copy.captureSize = texture.textureSize",
            f"copy.captureSize = Qt.size({bounds[0]}, {bounds[1]})"))
    if args.api:
        shutil.copyfile(HERE.parent / "sized-capture/ApiProbe.qml", config / "Capture.qml")
    # Hyprland appends a long instance signature; stay below sockaddr_un's limit.
    runtime = Path(tempfile.mkdtemp(prefix="cb-"))
    os.chmod(runtime, 0o700)
    parent_display = Path(os.environ["WAYLAND_DISPLAY"])
    if not parent_display.is_absolute():
        parent_display = Path(os.environ["XDG_RUNTIME_DIR"]) / parent_display
    env = os.environ.copy()
    for key in ("HYPRLAND_INSTANCE_SIGNATURE", "HYPRLAND_CMD", "NOTIFY_SOCKET", "DISPLAY",
                "QS_CONFIG_PATH", "QS_CONFIG_NAME", "QS_MANIFEST", "QT_QPA_PLATFORMTHEME"):
        env.pop(key, None)
    env.update(XDG_RUNTIME_DIR=str(runtime), WAYLAND_DISPLAY=str(parent_display),
               HYPRLAND_NO_SD_VARS="1", HYPRLAND_NO_RT="1", AQ_DRM_DEVICES="/dev/null",
               OMARCHY_CAPTURE_DIVISOR=str(divisor), QT_QPA_PLATFORM="wayland",
               CAPTURE_COUNT=str(count), CAPTURE_WIDTH=str(args.width), CAPTURE_HEIGHT=str(args.height))
    env["CAPTURE_TRANSPARENT"] = "1" if args.transparent and not args.api else "0"
    env.pop("QS_DISABLE_DMABUF", None)
    if args.shm:
        env["QS_DISABLE_DMABUF"] = "1"
    if args.trace:
        env["QT_LOGGING_RULES"] = "quickshell.wayland.buffer.debug=true;quickshell.wayland.buffer.dmabuf.debug=true"
        env["HYPRLAND_TRACE"] = "1"
    processes = []
    logs = []

    def start(command, name):
        log = (case / (name + ".log")).open("w")
        logs.append(log)
        process = subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        processes.append(process)
        return process

    def hypr(command):
        # The socket is discovered only inside the private runtime directory.
        paths = list((runtime / "hypr").glob("*/.socket.sock"))
        if not paths:
            return None
        assert len(paths) == 1
        with socket.socket(socket.AF_UNIX) as client:
            client.settimeout(10)
            client.connect(str(paths[0]))
            client.sendall(command.encode())
            data = bytearray()
            while chunk := client.recv(65536):
                data.extend(chunk)
        return data.decode()

    def ipc(*command):
        return subprocess.check_output([str(args.quickshell), "ipc", "-p", str(config / "Capture.qml"), "call", "--",
                                        "capture-benchmark", *command], env=env, text=True, stderr=subprocess.DEVNULL, timeout=15).strip()

    def status():
        assert consumer.poll() is None, f"Capture client exited: {case / 'capture.log'}"
        try:
            return json.loads(ipc("status"))
        except (subprocess.CalledProcessError, json.JSONDecodeError):
            return None

    try:
        compositor = start([str(args.binary), "--config", str(config_file)], "hyprland")
        wait_for(lambda: compositor.poll() is not None or list(runtime.glob("wayland-*.lock")), "compositor socket")
        assert compositor.poll() is None, f"Compositor exited: {case / 'hyprland.log'}"
        wait_for(lambda: hypr("j/version"), "private compositor IPC")
        assert hypr("/output create headless CAPTURE-BENCH") == "ok"
        wait_for(lambda: "CAPTURE-BENCH" in (hypr("j/monitors") or ""), "headless output")
        # Retain the nested backend's GPU connection, but close its host window.
        for monitor in json.loads(hypr("j/monitors")):
            if monitor["name"].startswith("WAYLAND-"):
                assert hypr("/output remove " + monitor["name"]) == "ok"
        env["WAYLAND_DISPLAY"] = str(next(runtime.glob("wayland-*.lock"))).removesuffix(".lock")
        env["HYPRLAND_INSTANCE_SIGNATURE"] = next((runtime / "hypr").iterdir()).name
        if args.subsurface:
            protocols = subprocess.check_output(["pkg-config", "--variable=pkgdatadir", "wayland-protocols"], text=True).strip()
            xml = str(Path(protocols) / "stable/xdg-shell/xdg-shell.xml")
            subprocess.run(["wayland-scanner", "client-header", xml, str(case / "xdg-shell-client.h")], check=True)
            subprocess.run(["wayland-scanner", "private-code", xml, str(case / "xdg-shell.c")], check=True)
            subprocess.run(["cc", "-O2", "-Wall", "-Wextra", "-Wno-unused-parameter", "-I", str(case), str(HERE / "subsurface.c"),
                            str(case / "xdg-shell.c"), "-lwayland-client", "-o", str(case / "subsurface")], check=True)
            sources = start([str(case / "subsurface")], "sources")
        else:
            sources = start(["qs", "-p", str(config / "Sources.qml")], "sources")
        wait_for(lambda: len(json.loads(hypr("j/clients"))) == count, "source windows")
        clients = json.loads(hypr("j/clients"))
        assert all(c["size"] == [args.width, args.height] and c["floating"] for c in clients), [(c["size"], c["floating"]) for c in clients]
        consumer = start([str(args.quickshell), "-p", str(config / "Capture.qml")], "capture")
        wait_for(lambda: (s := status()) and s["candidates"] == count, "capture client")
        time.sleep(1)
        if args.api:
            def check_probe(index, expected, minimum_frames=1):
                current = wait_for(lambda: (s := status()) and len(s["probes"]) > index
                    and s["probes"][index]["frames"] >= minimum_frames and s, "API capture")
                probe = current["probes"][index]
                assert probe["size"] == expected and probe["drops"] == 0, probe
                return current
            ipc("begin")
            requested = [[0, 0], [320, 180], [640, 360], [0, 128], [128, 0], [1, 1], [9000, 9000], [319, 173], [-1, -1]]
            expected = [native if args.legacy_server else fitted_size(native, b) for b in requested]
            for index, size in enumerate(expected):
                check_probe(index, size)
            # Retain content through a size change, including a change while a
            # request is still in flight. The latter takes effect next request.
            ipc("resize", "1", "640", "360")
            check_probe(1, native if args.legacy_server else fitted_size(native, [640, 360]), 2)
            ipc("race", "1")
            check_probe(1, native if args.legacy_server else fitted_size(native, [160, 90]), 3)
            ipc("refresh", "1")
            check_probe(1, native if args.legacy_server else fitted_size(native, [800, 450]), 4)
            final = status()
            assert final["probes"][0]["size"] == native, final
            # Starting and immediately destroying a frame must not poison other consumers.
            ipc("cancel")
            ipc("resize", "1", "320", "180")
            check_probe(1, native if args.legacy_server else fitted_size(native, [320, 180]), 5)
            if args.transparent:
                # Start opaque, then reuse buffers after the source becomes
                # transparent. The upper-right quadrant is beyond the old
                # monitor-sized clear on the rotated output.
                subprocess.run(["qs", "ipc", "-p", str(config / "Sources.qml"), "call", "--",
                    "capture-source", "setTransparent", "1"], env=env, check=True,
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)
                time.sleep(0.2)
                for index, requests, first_count in [(0, [[0, native[1]+1], [0, native[1]+2]], 2),
                                                      (1, [[321, 180], [320, 181]], 6)]:
                    for offset, bounds in enumerate(requests):
                        ipc("resize", str(index), str(bounds[0]), str(bounds[1]))
                        check_probe(index, native if args.legacy_server else fitted_size(native, bounds), first_count+offset)
            image = case / "api-previews.png"
            ipc("save", str(image))
            wait_for(lambda: status()["saved"] == str(image), "API preview snapshot")
            # First five include native, small, medium and both single-axis
            # constraints; the 1x1 fixture cannot preserve quadrant colors.
            verify_image(image, 5, transparent=args.transparent, background=(0, 0, 0), transparent_indices=[0, 1])
            final = status()
            final.update(api=True, legacy_server=args.legacy_server, native=native, image_checked=True, transparent=args.transparent)
            os.killpg(sources.pid, signal.SIGTERM)
            sources.wait(timeout=8)
            wait_for(lambda: (s := status()) and s["candidates"] == 0
                and all(p["drops"] == 1 for p in s["probes"]), "closed capture source cleanup")
            final["source_closed_cleanly"] = True
            (case / "results.json").write_text(json.dumps(final, indent=2) + "\n")
            print(json.dumps(final), flush=True)
            return [final]
        rows = []
        for run in range(args.runs):
            assert status()["views"] == 0
            frequency_before = cpu_frequencies_khz()
            before = [cpu_ms(p.pid) for p in (compositor, consumer)]
            ipc("begin")
            current = wait_for(lambda: (s := status()) and s["firstFrameMs"] is not None and s, "complete preview frame")
            after = [cpu_ms(p.pid) for p in (compositor, consumer)]
            assert current["missingAtReveal"] == 0 and current["pending"] == 0 and current["views"] == count, current
            expected = [math.ceil(math.floor(dimension * args.scale + 0.5) / divisor) for dimension in (args.width, args.height)]
            if args.per_request:
                expected = native if args.legacy_server else fitted_size(native, bounds)
            elif args.production_size:
                # Qt's screen DPR can round a fractional monitor scale.
                texture_bounds = [math.ceil(d * current["pixelRatio"] / 64) * 64 for d in [320, 180]]
                expected = native if args.legacy_server else fitted_size(native, texture_bounds)
            assert current["sizes"] == [expected] * count, current["sizes"]
            row = {"divisor": divisor, "windows": count, "run": run, "scale": args.scale, "transform": args.transform,
                   "forced_shm": args.shm, "trace": args.trace, "subsurface": args.subsurface,
                   "transparent": args.transparent,
                   "preparation_ms": current["preparationMs"], "first_complete_frame_ms": current["firstFrameMs"],
                   "hyprland_cpu_ms": after[0] - before[0], "quickshell_cpu_ms": after[1] - before[1],
                   "capture_size": expected, "single_buffer_bytes": count * expected[0] * expected[1] * 4,
                   "consumer_pixel_ratio": current["pixelRatio"],
                   "cpu_frequency_before_khz": frequency_before, "cpu_frequency_after_khz": cpu_frequencies_khz(),
                   "missing_at_reveal": current["missingAtReveal"]}
            if run == 0:
                screenshot = case / "previews.png"
                ipc("save", str(screenshot))
                wait_for(lambda: (s := status()) and s["saved"] == str(screenshot), "preview image")
                verify_image(screenshot, count, args.subsurface, args.transparent)
                row["image_checked"] = True
            if args.warm:
                ipc("close")
                time.sleep(0.1)
                ipc("reopen")
                warm = wait_for(lambda: (s := status()) and s["firstFrameMs"] is not None and s, "retained preview frame")
                assert warm["missingAtReveal"] == 0 and warm["preparationMs"] == 0, warm
                row["warm_first_complete_frame_ms"] = warm["firstFrameMs"]
                row["warm_preparation_ms"] = warm["preparationMs"]
            print(json.dumps(row), flush=True)
            rows.append(row)
            (case / "results.json").write_text(json.dumps(rows, indent=2) + "\n")
            ipc("reset")
            wait_for(lambda: (s := status()) and s["views"] == 0, "capture cleanup")
            time.sleep(0.25)
        return rows
    finally:
        for process in reversed(processes):
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=8)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
        for log in logs:
            log.close()
        for log in runtime.glob("hypr/*/hyprland.log"):
            shutil.copyfile(log, case / "compositor.log")
        # Preserve the private runtime directory for diagnostics on failure.


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--quickshell", type=Path, default=Path("/usr/bin/qs"))
    parser.add_argument("--per-request", action="store_true", help="Exercise draft per-request size API instead of global divisor")
    parser.add_argument("--production-size", action="store_true", help="Use production consumer texture bounds")
    parser.add_argument("--api", action="store_true", help="Validate concurrent native/scaled requests and size changes")
    parser.add_argument("--legacy-server", action="store_true", help="Expect native-size fallback from a v2 compositor")
    parser.add_argument("--warm", action="store_true", help="Also measure reopening each retained composition")
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--divisors", type=int, nargs="+", default=[1, 2, 4, 8])
    parser.add_argument("--windows", type=int, nargs="+", default=[1, 32, 64])
    parser.add_argument("--runs", type=int, default=6)
    parser.add_argument("--width", type=int, default=2560)
    parser.add_argument("--height", type=int, default=1440)
    parser.add_argument("--scale", type=float, default=1)
    parser.add_argument("--transform", type=int, default=0)
    parser.add_argument("--shm", action="store_true")
    parser.add_argument("--trace", action="store_true")
    parser.add_argument("--subsurface", action="store_true")
    parser.add_argument("--transparent", action="store_true", help="Check alpha with a transparent source quadrant")
    args = parser.parse_args()
    args.binary = args.binary.resolve(strict=True)
    args.quickshell = args.quickshell.resolve(strict=True)
    args.output = args.output.resolve()
    assert not args.api or args.windows == [1]
    assert args.runs > 0 and all(1 <= n <= 64 for n in args.windows)
    assert all(n in (1, 2, 4, 8) for n in args.divisors)
    assert not args.subsurface or args.windows == [1], "Subsurface fixture requires --windows 1"
    results = []
    for count in args.windows:
        for divisor in args.divisors:
            results.extend(benchmark(args, divisor, count))
    (args.output / "results.json").write_text(json.dumps(results, indent=2) + "\n")


if __name__ == "__main__":
    main()
