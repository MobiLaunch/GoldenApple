#!/usr/bin/env python3
"""Exercise TextEdit's document workflow under Darling (milestone M3).

Opens an existing plain-text document, edits, saves and quits, then reopens
the saved file and repeats. Each save must equal the previous contents with
only that session's typed marker inserted, so a lost or replaced document
fails wherever the insertion point lands. Use a fresh, disposable prefix and
an X11 display (xvfb-run -a on CI). Only the document under --output changes.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

spec = importlib.util.spec_from_file_location("gui", Path(__file__).with_name("test-gui.py"))
gui = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gui)

DOCUMENT = "GoldenGateNote.txt"
BASELINE = "Golden Gate TextEdit document workflow\nThis line must survive two edit sessions.\n"


def marker_inserted(before, after, marker):
    """True when after is before plus exactly one copy of marker, anywhere."""
    if after.count(marker) != before.count(marker) + 1:
        return False
    index = after.find(marker)
    while index >= 0:
        if after[:index] + after[index + len(marker):] == before:
            return True
        index = after.find(marker, index + 1)
    return False


def visible_windows():
    search = subprocess.run(["xdotool", "search", "--onlyvisible", "--name", "."],
                            capture_output=True, text=True)
    windows = []
    for window in search.stdout.split():
        name = subprocess.run(["xdotool", "getwindowname", window], capture_output=True, text=True)
        windows.append(f"{window}: {name.stdout.strip()}")
    return windows


def print_diagnostics(output, lines=150):
    """CI artifacts are not always reachable; put the key evidence in the job log."""
    for path in sorted(output.glob("session-*.log")) + sorted(output.glob("live-backtrace*.log")):
        text = path.read_text(errors="replace").splitlines()
        print(f"===== {path.name} (last {min(lines, len(text))} of {len(text)} lines) =====")
        print("\n".join(text[-lines:]))


def run_session(number, binary, document, env, output, result):
    """Open, edit, save and quit once; return the saved text."""
    before = document.read_text()
    marker = f" [session {number} {time.monotonic_ns()}]"
    tag = f"session-{number}"
    with (output / f"{tag}.log").open("w") as log:
        process = subprocess.Popen(["darling", str(binary), "-NSOpen", "/Volumes/SystemRoot" + str(document)],
                                   env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    result["sessions"].append({"session": number, "marker": marker})
    session = result["sessions"][-1]
    try:
        def phase(name):
            result["phase"] = f"{tag}:{name}"
            code = process.poll()
            if code is not None:
                raise RuntimeError(f"TextEdit exited during {tag} {name}: {code}")

        def find_window():
            phase("open-document")
            search = subprocess.run(["xdotool", "search", "--onlyvisible", "--name", "GoldenGateNote"],
                                    capture_output=True, text=True)
            lines = search.stdout.strip().splitlines()
            return lines[0] if search.returncode == 0 and lines else None
        try:
            window = gui.wait_until(find_window, 90)
        except RuntimeError:
            # An untitled window or an error alert means the document never
            # opened; record what is on screen instead of only a timeout.
            session["visible_windows"] = visible_windows()
            subprocess.run(["xwd", "-silent", "-root", "-out", str(output / f"{tag}-screen.xwd")],
                           capture_output=True, check=False)
            raise RuntimeError(f"{tag}: no document window; visible: {session['visible_windows']}") from None
        session["window_title"] = gui.xdo("getwindowname", window)
        result["checks"].append(f"{tag}-document-window")

        def shot(name):
            completed = subprocess.run(["xwd", "-silent", "-id", window, "-out", str(output / f"{tag}-{name}.xwd")],
                                       capture_output=True, text=True)
            if completed.returncode:
                raise RuntimeError(f"Screenshot {tag}-{name}: {completed.stderr.strip()}")
            return output / f"{tag}-{name}.xwd"

        def rendered():
            phase("rendering")
            return gui.surface_has_content(shot("opened"))
        gui.wait_until(rendered, 30)
        result["checks"].append(f"{tag}-rendered")

        phase("edit")
        gui.xdo("windowfocus", window)
        geometry = dict(line.split("=", 1) for line in gui.xdo("getwindowgeometry", "--shell", window).splitlines()
                        if "=" in line)
        gui.xdo("mousemove", "--window", window, int(geometry["WIDTH"]) // 2, int(geometry["HEIGHT"]) // 2)
        gui.xdo("click", 1)
        gui.xdo("type", "--clearmodifiers", "--delay", 20, marker)
        time.sleep(0.5)
        phase("edited")
        shot("edited")

        # Darling's X11 backend maps Super to Cocoa's Command modifier.
        phase("save")
        gui.xdo("key", "--clearmodifiers", "super+s")

        def saved():
            phase("save")
            text = document.read_text(errors="replace")
            return text if text != before else None
        try:
            after = gui.wait_until(saved, 20)
        except RuntimeError as error:
            shot("unsaved")
            raise RuntimeError(f"{tag}: document was not written after Command-S") from error
        time.sleep(0.5)
        after = document.read_text(errors="replace")
        shutil.copyfile(document, output / f"{tag}-saved.txt")
        if not marker_inserted(before, after, marker):
            raise RuntimeError(f"{tag}: saved document lost or changed existing content")
        result["checks"].append(f"{tag}-saved-without-loss")
        shot("saved")

        phase("quit")
        gui.xdo("key", "--clearmodifiers", "super+q")
        try:
            code = process.wait(timeout=20)
        except subprocess.TimeoutExpired as error:
            shot("quit-timeout")
            raise RuntimeError(f"{tag}: TextEdit did not quit after Command-Q") from error
        session["launcher_exit"] = code
        if code != 0:
            raise RuntimeError(f"{tag}: TextEdit quit with exit {code}")
        result["checks"].append(f"{tag}-clean-quit")
        return after
    finally:
        session["launcher_exit_before_cleanup"] = process.poll()
        if process.poll() is None:
            gui.capture_live_backtrace(output, binary)
            try:
                process.terminate()
                process.wait(timeout=5)
            except (OSError, subprocess.TimeoutExpired):
                pass


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
    binary = app / "Contents/MacOS/TextEdit"
    if not binary.is_file():
        parser.error("TextEdit executable is missing")
    output.mkdir(parents=True, exist_ok=True)
    documents = output / "documents"
    documents.mkdir(exist_ok=True)
    document = documents / DOCUMENT
    document.write_text(BASELINE)
    env = {**os.environ, "DPREFIX": str(prefix)}
    result = {"passed": False, "checks": [], "binary": str(binary), "phase": "startup", "sessions": []}
    try:
        run_session(1, binary, document, env, output, result)
        # Session 2's save must equal session 1's save plus one marker, so it
        # proves the reopened document loaded the saved contents intact.
        run_session(2, binary, document, env, output, result)
        result["checks"].append("reopened-without-data-loss")
        result["phase"] = "complete"
        result["passed"] = True
    except (OSError, RuntimeError, KeyError, ValueError, subprocess.CalledProcessError) as error:
        result["error"] = str(error)
    finally:
        for name, command in (("processes.log", ["ps", "-eo", "pid,ppid,stat,args"]),
                              ("coredumps.log", ["coredumpctl", "--no-pager", "list", "--since", "10 minutes ago"])):
            try:
                collected = subprocess.run(command, capture_output=True, text=True, timeout=10)
                (output / name).write_text(collected.stdout + collected.stderr)
            except (OSError, subprocess.TimeoutExpired) as error:
                (output / name).write_text(str(error) + "\n")
        (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
        if prefix.exists():
            try:
                subprocess.run(["darling", "shutdown"], env=env, stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, timeout=10, check=False)
            except (OSError, subprocess.TimeoutExpired):
                result["cleanup"] = "Disposable-prefix shutdown timed out"
        (output / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))
    if not result["passed"]:
        print_diagnostics(output)
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
