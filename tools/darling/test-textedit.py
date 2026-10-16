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


def launch_command(binary, document, output, number, xtrace):
    """The Darling launcher command and extra environment for one session.

    With xtrace, Darling's libxtrace logs every BSD syscall and Mach message
    per thread, so a hang shows the last call each thread made."""
    target = ["/Volumes/SystemRoot" + str(binary), "-NSOpen", "/Volumes/SystemRoot" + str(document)]
    if not xtrace:
        return ["darling", str(binary), *target[1:]], {}
    logs = output / "xtrace"
    logs.mkdir(exist_ok=True)
    return ["darling", "shell", "xtrace", *target], {
        "XTRACE_NO_COLOR": "1",
        "XTRACE_LOG_FILE": f"/Volumes/SystemRoot{logs}/session-{number}",
        "XTRACE_LOG_FILE_PER_THREAD": "1",
    }


def read_windows(output, tag, windows):
    """OCR each visible window, so an alert's message reaches the job log."""
    if not (shutil.which("convert") and shutil.which("tesseract")):
        return
    for entry in windows:
        window = entry.split(":", 1)[0]
        image = output / f"{tag}-window-{window}"
        captured = subprocess.run(["xwd", "-silent", "-id", window, "-out", f"{image}.xwd"], capture_output=True)
        converted = captured.returncode == 0 and subprocess.run(
            ["convert", f"xwd:{image}.xwd", "-resize", "200%", f"{image}.png"], capture_output=True).returncode == 0
        if not converted:
            continue
        text = subprocess.run(["tesseract", f"{image}.png", "-"], capture_output=True, text=True, timeout=60).stdout
        Path(f"{image}.txt").write_text(f"{entry}\n{text.strip()}\n")


def print_diagnostics(output, lines=150):
    """CI artifacts are not always reachable; put the key evidence in the job log."""
    for path in sorted(output.glob("session-*.log")):
        text = path.read_text(errors="replace").splitlines()
        print(f"===== {path.name} (last {min(lines, len(text))} of {len(text)} lines) =====")
        print("\n".join(text[-lines:]))
    for path in sorted(output.glob("session-*-window-*.txt")):
        print(f"===== {path.stem} (OCR) =====")
        print(path.read_text(errors="replace").strip())
    traces = sorted((output / "xtrace").glob("session-*"))
    # Whether TextEdit ever touched the document, wherever the thread ended.
    access = [f"{path.name}: {line}" for path in traces
              for line in path.read_text(errors="replace").splitlines() if Path(DOCUMENT).stem in line]
    if traces:
        print(f"===== xtrace document access ({min(lines // 3, len(access))} of {len(access)} lines) =====")
        print("\n".join(access[:lines // 3]))
    for path in traces:
        text = path.read_text(errors="replace").splitlines()
        print(f"===== xtrace {path.name} (last {min(lines // 3, len(text))} of {len(text)} lines) =====")
        print("\n".join(text[-(lines // 3):]))
    processes = output / "live-processes.log"
    if processes.exists():
        print("===== Darling processes =====")
        print("\n".join(line for line in processes.read_text(errors="replace").splitlines()
                        if "darling" in line.lower() or "TextEdit" in line or "launchd" in line))
    for path in sorted(output.glob("live-backtrace*.log")):
        text = path.read_text(errors="replace").splitlines()
        end = next((i for i, line in enumerate(text) if "Mapped address spaces" in line), len(text))
        print(f"===== {path.name} (thread stacks, {min(end, 4 * lines)} of {len(text)} lines) =====")
        print("\n".join(symbolize(text[:min(end, 4 * lines)], mappings(text[end:]))))


def mappings(lines):
    """gdb's `info proc mappings`: (start, end, file offset, path) for files."""
    found = []
    for line in lines:
        fields = line.split()
        if len(fields) >= 6 and fields[0].startswith("0x") and fields[-1].startswith("/"):
            try:
                found.append((int(fields[0], 16), int(fields[1], 16), int(fields[3], 16), fields[-1]))
            except ValueError:
                continue
    return found


def symbolize(stack, maps):
    """gdb cannot read Darling's Mach-O images; name frames as image+offset
    and, where llvm-symbolizer can read the image, its function."""
    tool = shutil.which("llvm-symbolizer") or next(
        (p for p in sorted(Path("/usr/bin").glob("llvm-symbolizer-*"), reverse=True)), None)
    out = []
    for line in stack:
        parts = line.split()
        if len(parts) >= 2 and parts[0].startswith("#") and parts[1].startswith("0x"):
            address = int(parts[1], 16)
            hit = next(((start, offset, image) for start, end, offset, image in maps
                        if start <= address < end), None)
            if hit:
                start, offset, image = hit
                # A dylib's __TEXT maps from file offset 0 at vmaddr 0.
                vm = address - start + offset
                name = ""
                if tool:
                    try:
                        resolved = subprocess.run([str(tool), "--obj=" + image, hex(vm)], capture_output=True,
                                                  text=True, timeout=10).stdout.split("\n")[0].strip()
                        name = "" if resolved in ("", "??") else " " + resolved
                    except (OSError, subprocess.TimeoutExpired):
                        pass
                line = f"{line}  <{Path(image).name}+{hex(vm)}{name}>"
        out.append(line)
    return out


def run_session(number, binary, document, env, output, result, xtrace=False):
    """Open, edit, save and quit once; return the saved text."""
    before = document.read_text()
    marker = f" [session {number} {time.monotonic_ns()}]"
    tag = f"session-{number}"
    command, extra = launch_command(binary, document, output, number, xtrace)
    with (output / f"{tag}.log").open("w") as log:
        process = subprocess.Popen(command, env={**env, **extra}, stdout=log, stderr=subprocess.STDOUT,
                                   start_new_session=True)
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
            read_windows(output, tag, session["visible_windows"])
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
    parser.add_argument("--xtrace", action="store_true",
                        help="Diagnose: trace syscalls and Mach messages per thread (slow)")
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
    result = {"passed": False, "checks": [], "binary": str(binary), "phase": "startup", "sessions": [],
              "xtrace": args.xtrace}
    try:
        run_session(1, binary, document, env, output, result, args.xtrace)
        # Session 2's save must equal session 1's save plus one marker, so it
        # proves the reopened document loaded the saved contents intact.
        run_session(2, binary, document, env, output, result, args.xtrace)
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
