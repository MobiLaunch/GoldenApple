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
import subprocess
import time


def xdo(*args):
    return subprocess.check_output(["xdotool", *map(str, args)], text=True).strip()


def wait_until(predicate, seconds):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.25)
    raise RuntimeError("Timed out waiting for the fixture")


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
    result = {"passed": False, "checks": [], "binary": str(binary)}
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
            subprocess.run(["xwd", "-silent", "-id", window, "-out", str(output / "opened.xwd")], check=True)
            # No window manager is required under Xvfb. Focus the window directly.
            xdo("windowfocus", window)
            xdo("mousemove", "--window", window, 220, 120)
            xdo("click", 1)
            # Darling's X11 backend maps Mod4/Super to Cocoa's Command modifier.
            xdo("key", "--clearmodifiers", "super+a")
            marker = "Darling GUI save regression " + str(time.monotonic_ns())
            xdo("type", "--clearmodifiers", "--delay", 20, marker)
            # Measure the actual surface: Darling's titlebar can change its
            # total height, but the button stays 36px above the bottom edge.
            geometry = dict(line.split("=", 1) for line in xdo("getwindowgeometry", "--shell", window).splitlines() if "=" in line)
            xdo("mousemove", "--window", window, 60, int(geometry["HEIGHT"]) - 36)
            xdo("click", 1)
            def saved_document():
                for path in prefix.rglob("Darling-ControllerLab.txt") if prefix.exists() else []:
                    if marker in path.read_text(errors="replace"):
                        return path
                return None
            saved = wait_until(saved_document, 15)
            shutil.copyfile(saved, output / "saved-document.txt")
            result["checks"].extend(["text-input", "target-action", "utf8-save"])
            xdo("windowsize", window, 760, 480)
            time.sleep(0.5)
            subprocess.run(["xwd", "-silent", "-id", window, "-out", str(output / "resized.xwd")], check=True)
            result["checks"].append("resize-without-crash")
            xdo("windowclose", window)
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
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
        # Stop only the disposable prefix, never the user's regular Darling.
        if prefix.exists():
            try:
                subprocess.run(["darling", "shutdown"], env=env, stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, timeout=10, check=False)
            except subprocess.TimeoutExpired:
                result["cleanup"] = "Disposable-prefix shutdown timed out"
        (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
