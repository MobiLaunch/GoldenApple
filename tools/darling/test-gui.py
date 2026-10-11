#!/usr/bin/env python3
"""Exercise the unchanged Intel fixture with a real Darling/X11 backend.

Use a fresh, disposable prefix. Run with xvfb-run on CI or in a test desktop.
Logs, screenshots and a JSON result distinguish a visible, usable GUI from a
process that merely survived startup. This script changes only the fixture.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import time


def xdo(*args):
    completed = subprocess.run(["xdotool", *map(str, args)], capture_output=True, text=True)
    if completed.returncode:
        raise RuntimeError(f"xdotool {args}: exit {completed.returncode}: {completed.stderr.strip()}")
    return completed.stdout.strip()


def surface_has_content(path):
    """Reject uniform startup surfaces; this alone does not prove usable UI."""
    data = path.read_bytes()
    if len(data) < 100:
        raise RuntimeError("Truncated XWD header")
    header = struct.unpack(">25I", data[:100])
    size, version, image_format, depth, width, height = header[:6]
    byte_order, bits, stride, colors = header[7], header[11], header[12], header[19]
    if version != 7 or image_format != 2 or depth not in (24, 32) or bits not in (24, 32):
        raise RuntimeError(f"Unsupported XWD format: version={version}, format={image_format}, depth={depth}, bits={bits}")
    pixels = data[size + 12 * colors:]
    if len(pixels) < stride * height or not width or not height:
        raise RuntimeError("Truncated XWD pixels")
    masks = header[14] | header[15] | header[16]
    seen = set()
    # Ignore row padding and unused alpha bits, which can look nonuniform.
    for y in range(height):
        for x in range(width):
            start = y * stride + x * (bits // 8)
            value = int.from_bytes(pixels[start:start + bits // 8], "little" if byte_order == 0 else "big") & masks
            seen.add(value)
            if len(seen) >= 4:
                return True
    return False


def wait_until(predicate, seconds):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.25)
    raise RuntimeError("Timed out waiting for the fixture")


def capture_live_backtrace(output, binary):
    """Inspect only the exact fixture process before disposable-prefix cleanup."""
    try:
        listing = subprocess.run(["ps", "-eo", "pid=,args="], capture_output=True,
                                 text=True, timeout=10)
        (output / "live-processes.log").write_text(listing.stdout + listing.stderr)
        # Mach-O argv[0] has the SystemRoot prefix, unlike the Linux launcher.
        matches = []
        for line in listing.stdout.splitlines():
            fields = line.strip().split(None, 2)
            if len(fields) >= 2 and fields[1] == "/Volumes/SystemRoot" + str(binary):
                matches.append(int(fields[0]))
        if not matches:
            (output / "live-backtrace.log").write_text("No live fixture process found.\n")
        for pid in matches:
            traced = subprocess.run(["sudo", "-n", "gdb", "-batch", "-p", str(pid),
                                     "-ex", "thread apply all bt 40", "-ex", "info proc mappings",
                                     "-ex", "detach"], capture_output=True, text=True, timeout=20)
            (output / f"live-backtrace-{pid}.log").write_text(traced.stdout + traced.stderr)
    except (OSError, subprocess.TimeoutExpired) as error:
        (output / "live-backtrace.log").write_text(str(error) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--prefix", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    app, prefix, output = args.app.resolve(), args.prefix.resolve(), args.output.resolve()
    if not os.environ.get("DISPLAY"):
        parser.error("An X11 display is required; use xvfb-run -a")
    for command in ("darling", "xdotool", "xwd"):
        if not shutil.which(command):
            parser.error(f"Missing test tool: {command}")
    if prefix.exists():
        parser.error("Use a fresh prefix; this tool will not change an existing one")
    binary = app / "Contents/MacOS/ControllerLab"
    if not binary.is_file():
        parser.error("ControllerLab executable is missing")
    output.mkdir(parents=True, exist_ok=True)
    env = {**os.environ, "DPREFIX": str(prefix)}
    result = {"passed": False, "checks": [], "binary": str(binary), "phase": "startup", "events": []}
    process = None
    window = None
    try:
        with (output / "darling.log").open("w") as log:
            process = subprocess.Popen(["darling", str(binary)], env=env,
                                       stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            def find_window():
                if process.poll() is not None:
                    raise RuntimeError(f"Darling exited before opening a window: {process.returncode}")
                search = subprocess.run(["xdotool", "search", "--onlyvisible", "--name", "^Darling Controller Lab$"],
                                        capture_output=True, text=True)
                return search.stdout.strip().splitlines()[0] if search.returncode == 0 and search.stdout.strip() else None
            window = wait_until(find_window, 60)
            result["checks"].append("visible-window")
            def checkpoint(phase, capture=True):
                result["phase"] = phase
                code = process.poll()
                result["events"].append({"phase": phase, "launcher_exit": code})
                if code is not None:
                    raise RuntimeError(f"Darling exited during {phase}: {code}")
                geometry = xdo("getwindowgeometry", "--shell", window)
                if capture:
                    completed = subprocess.run(["xwd", "-silent", "-id", window, "-out", str(output / f"{phase}.xwd")], capture_output=True, text=True)
                    if completed.returncode:
                        raise RuntimeError(f"Screenshot during {phase}: {completed.stderr.strip()}")
                return dict(line.split("=", 1) for line in geometry.splitlines() if "=" in line)
            def rendered():
                checkpoint("rendering", capture=False)
                completed = subprocess.run(["xwd", "-silent", "-id", window, "-out", str(output / "opened.xwd")], capture_output=True, text=True)
                if completed.returncode:
                    raise RuntimeError(f"Startup screenshot: {completed.stderr.strip()}")
                return surface_has_content(output / "opened.xwd")
            wait_until(rendered, 30)
            result["checks"].append("nonuniform-rendered-surface")
            # No window manager is required under Xvfb. Focus the window directly.
            result["phase"] = "focus"
            xdo("windowfocus", window)
            checkpoint("focused")
            result["phase"] = "editor-click"
            xdo("mousemove", "--window", window, 220, 120)
            xdo("click", 1)
            checkpoint("editor-clicked")
            # Darling's X11 backend maps Mod4/Super to Cocoa's Command modifier.
            result["phase"] = "select-all"
            xdo("key", "--clearmodifiers", "super+a")
            checkpoint("selected")
            marker = "Darling GUI save regression " + str(time.monotonic_ns())
            result["phase"] = "typing"
            xdo("type", "--clearmodifiers", "--delay", 20, marker)
            # Measure the actual surface: Darling's titlebar can change its
            # total height, but the button stays 36px above the bottom edge.
            geometry = checkpoint("typed")
            result["phase"] = "save-click"
            xdo("mousemove", "--window", window, 60, int(geometry["HEIGHT"]) - 36)
            xdo("click", 1)
            checkpoint("save-clicked")
            def saved_document():
                for path in prefix.rglob("Darling-ControllerLab.txt") if prefix.exists() else []:
                    if marker in path.read_text(errors="replace"):
                        return path
                return None
            saved = wait_until(saved_document, 15)
            shutil.copyfile(saved, output / "saved-document.txt")
            result["checks"].extend(["text-input", "target-action", "utf8-save"])
            result["phase"] = "resize"
            xdo("windowsize", window, 760, 480)
            time.sleep(0.5)
            subprocess.run(["xwd", "-silent", "-id", window, "-out", str(output / "resized.xwd")], check=True)
            result["checks"].append("resize-without-crash")
            result["phase"] = "close"
            # windowclose destroys the X resource without Cocoa close callbacks.
            # windowquit sends WM_DELETE_WINDOW, as a window manager would.
            xdo("windowquit", window)
            try:
                code = process.wait(timeout=15)
            except subprocess.TimeoutExpired as error:
                raise RuntimeError("App did not exit after closing its last window") from error
            if code != 0:
                raise RuntimeError(f"App closed with exit {code}")
            result["checks"].append("clean-exit")
            result["passed"] = True
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        result["error"] = str(error)
    finally:
        # Record natural termination before cleanup can replace it with SIGTERM.
        result["launcher_exit_before_cleanup"] = process.poll() if process is not None else None
        for name, command in (("processes.log", ["ps", "-eo", "pid,ppid,stat,args"]),
                              ("kernel.log", ["sudo", "-n", "journalctl", "-k", "--since", "5 minutes ago", "--no-pager"]),
                              ("coredumps.log", ["coredumpctl", "--no-pager", "list", "--since", "5 minutes ago"]),
                              ("coredump-info.log", ["sudo", "-n", "coredumpctl", "--no-pager", "info", "--since", "5 minutes ago"])):
            try:
                collected = subprocess.run(command, capture_output=True, text=True, timeout=10)
                (output / name).write_text(collected.stdout + collected.stderr)
            except (OSError, subprocess.TimeoutExpired) as error:
                (output / name).write_text(str(error) + "\n")
        if not result["passed"]:
            capture_live_backtrace(output, binary)
            try:
                core = output / "mldr.core"
                loader = "/usr/local/libexec/darling/usr/libexec/darling/mldr"
                dumped = subprocess.run(["sudo", "-n", "coredumpctl", "dump", "--since", "5 minutes ago",
                                         "--output", str(core), loader], capture_output=True, text=True, timeout=15)
                (output / "coredump-export.log").write_text(dumped.stdout + dumped.stderr)
                if dumped.returncode == 0:
                    # Use root to read the coredump without changing its ownership.
                    traced = subprocess.run(["sudo", "-n", "gdb", "-batch", "-ex", "info registers",
                                             "-ex", "thread apply all bt full", "-ex", "info proc mappings",
                                             loader, str(core)], capture_output=True, text=True, timeout=20)
                    (output / "backtrace.log").write_text(traced.stdout + traced.stderr)
                    subprocess.run(["sudo", "-n", "chmod", "0644", str(core)],
                                   capture_output=True, timeout=10, check=False)
            except (OSError, subprocess.TimeoutExpired) as error:
                (output / "coredump-export.log").write_text(str(error) + "\n")
        # Persist the natural failure before touching a privileged launcher.
        # Darling can change credentials, making direct terminate() fail.
        (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
        if process is not None and process.poll() is None:
            try:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
            except OSError as error:
                result["launcher_cleanup_error"] = str(error)
        # Stop only the disposable prefix, never the user's regular Darling.
        if prefix.exists():
            try:
                subprocess.run(["darling", "shutdown"], env=env, stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, timeout=10, check=False)
            except (OSError, subprocess.TimeoutExpired):
                result["cleanup"] = "Disposable-prefix shutdown timed out"
        (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
