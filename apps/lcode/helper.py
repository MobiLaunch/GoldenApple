#!/usr/bin/env python3
"""LCode backend.

    helper.py serve        JSON lines on stdin/stdout, for the LCode window
    helper.py <command>    one-shot commands (tests, scripts):
        create PARENT TEMPLATE NAME [ORG_ID]   new project, prints its root
        project PATH                            project description
        diagnostics ROOT                        parse compiler output on stdin

Requests are {"id": n, "cmd": "...", ...}; every request gets one reply,
{"id": n, "ok": true, ...} or {"id": n, "ok": false, "error": "..."}.
Unsolicited events are {"event": "...", ...}:

    tree.changed                    the project's files changed on disk
    task.started  {gen, kind, title}
    task.log      {gen, text}       build/test/clean output
    task.progress {gen, done, total, message}
    task.issue    {gen, severity, message, path, line, column}
    task.finished {gen, kind, code, cancelled, errors, warnings}
    run.started   {gen, product, destination}
    run.output    {gen, stream, text}
    run.exited    {gen, code}
    sim.state     {power: "off" | "booting" | "on", error?}
    sim.frame     {frame, seq, w, h, window, top, bottom}
"""
from __future__ import annotations

import codecs
import json
import os
import pathlib
import shutil
import signal
import subprocess
import sys
import threading
import time

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import lcode_project as proj  # noqa: E402

_out = threading.Lock()


def emit(obj: dict) -> None:
    line = json.dumps(obj, separators=(",", ":"))
    with _out:
        try:
            sys.stdout.write(line + "\n")
            sys.stdout.flush()
        except BrokenPipeError:
            os._exit(0)


# ----------------------------------------------------------------- settings

def config_path() -> pathlib.Path:
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return pathlib.Path(base) / "golden-gate" / "lcode.json"


DEFAULTS = {
    "swiftPath": "",
    "fontSize": 13,
    "tabWidth": 4,
    "showMinimap": True,
    "showWelcome": True,
    "defaultSimulator": "lphone-16",
    "organizationName": "",
    "organizationIdentifier": "com.example",
    "recent": [],
}


def load_settings() -> dict:
    data = dict(DEFAULTS)
    data.update(proj.read_json(config_path()))
    data["recent"] = [p for p in data.get("recent", []) if isinstance(p, str) and os.path.isdir(p)]
    return data


def save_settings(data: dict) -> None:
    proj.write_json(config_path(), data)


def swift_executable() -> str | None:
    configured = load_settings().get("swiftPath") or ""
    if configured:
        return configured
    if os.environ.get("LCODE_SWIFT"):
        return os.environ["LCODE_SWIFT"]
    return shutil.which("swift")


def swift_version(path: str | None) -> str:
    if not path:
        return ""
    try:
        out = subprocess.run([path, "--version"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=10)
        return out.stdout.strip().splitlines()[0] if out.returncode == 0 and out.stdout.strip() else ""
    except (OSError, subprocess.TimeoutExpired):
        return ""


# ---------------------------------------------------------------- processes

class Proc:
    """A child process in its own session, streaming decoded output."""

    def __init__(self, argv: list[str], cwd: str, env: dict | None, on_text, on_exit):
        self.p = subprocess.Popen(argv, cwd=cwd, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE, start_new_session=True)
        self.done = threading.Event()
        readers = [threading.Thread(target=self._read, args=(self.p.stdout, "stdout", on_text), daemon=True),
                   threading.Thread(target=self._read, args=(self.p.stderr, "stderr", on_text), daemon=True)]
        for r in readers:
            r.start()

        def wait() -> None:
            for r in readers:
                r.join()
            code = self.p.wait()
            self.done.set()
            on_exit(code if code >= 0 else None)
        threading.Thread(target=wait, daemon=True).start()

    @staticmethod
    def _read(pipe, stream: str, on_text) -> None:
        decoder = codecs.getincrementaldecoder("utf-8")("replace")
        while True:
            chunk = os.read(pipe.fileno(), 8192)
            if not chunk:
                break
            text = decoder.decode(chunk)
            if text:
                on_text(stream, text)
        tail = decoder.decode(b"", final=True)
        if tail:
            on_text(stream, tail)

    def write(self, text: str) -> None:
        try:
            self.p.stdin.write(text.encode())
            self.p.stdin.flush()
        except (OSError, ValueError):
            pass

    def stop(self) -> None:
        if self.done.is_set():
            return
        try:
            os.killpg(self.p.pid, signal.SIGTERM)
        except ProcessLookupError:
            return

        def force() -> None:
            if not self.done.wait(1.5):
                try:
                    os.killpg(self.p.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        threading.Thread(target=force, daemon=True).start()


# ---------------------------------------------------------------- simulator

class Simulator:
    """A private Xvfb display plus the agent that mirrors it (lcode_sim.py)."""

    def __init__(self) -> None:
        self.lock = threading.RLock()
        self.power = "off"
        self.xvfb: subprocess.Popen | None = None
        self.agent: subprocess.Popen | None = None
        self.display = ""
        self.app: Proc | None = None
        runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/tmp/lcode-{os.getuid()}"
        self.frame_dir = os.path.join(runtime, "lcode", str(os.getpid()))

    def _set_power(self, power: str, error: str = "") -> None:
        self.power = power
        emit({"event": "sim.state", "power": power, **({"error": error} if error else {})})

    def boot(self, side: int, w: int, h: int) -> None:
        with self.lock:
            if self.power == "on":
                self.region(w, h)
                return
            xvfb = shutil.which("Xvfb")
            if not xvfb:
                self._set_power("off", "Xvfb is not installed. Install it with: sudo pacman -S xorg-server-xvfb")
                raise RuntimeError("Xvfb is not installed.")
            self._set_power("booting")
            number = next((n for n in range(90, 400) if not os.path.exists(f"/tmp/.X11-unix/X{n}")
                           and not os.path.exists(f"/tmp/.X{n}-lock")), None)
            if number is None:
                self._set_power("off", "No free X display number.")
                raise RuntimeError("No free X display number.")
            self.display = f":{number}"
            self.xvfb = subprocess.Popen([xvfb, self.display, "-screen", "0", f"{side}x{side}x24", "-nolisten", "tcp",
                                          "-dpi", "96", "-br", "-noreset"],
                                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            deadline = time.monotonic() + 10
            while not os.path.exists(f"/tmp/.X11-unix/X{number}"):
                if self.xvfb.poll() is not None or time.monotonic() > deadline:
                    self._kill_server()
                    self._set_power("off", "The simulator display failed to start.")
                    raise RuntimeError("The simulator display failed to start.")
                time.sleep(0.05)
            time.sleep(0.2)
            self.agent = subprocess.Popen([sys.executable, str(HERE / "lcode_sim.py"), "agent", self.display,
                                           self.frame_dir, str(w), str(h)],
                                          stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)
            threading.Thread(target=self._frames, args=(self.agent,), daemon=True).start()
            self._set_power("on")

    def _frames(self, agent: subprocess.Popen) -> None:
        for line in agent.stdout:
            try:
                emit({"event": "sim.frame", **json.loads(line)})
            except ValueError:
                pass

    def _agent(self, cmd: dict) -> None:
        with self.lock:
            if self.agent and self.agent.poll() is None:
                try:
                    self.agent.stdin.write(json.dumps(cmd) + "\n")
                    self.agent.stdin.flush()
                except (OSError, ValueError):
                    pass

    def region(self, w: int, h: int) -> None:
        self._agent({"t": "region", "w": int(w), "h": int(h)})

    def input(self, cmd: dict) -> None:
        self._agent(cmd)

    def launch(self, exe: str, cwd: str, device: dict, on_text, on_exit) -> Proc:
        env = dict(os.environ)
        env.pop("WAYLAND_DISPLAY", None)
        env.update({
            "DISPLAY": self.display,
            "GDK_BACKEND": "x11", "GDK_SCALE": "1", "GSK_RENDERER": "cairo",
            # Server-side decorations, of which there are none without a window
            # manager: plain windows fill the screen like a phone app.
            "GTK_CSD": "0", "GTK_A11Y": "none", "NO_AT_BRIDGE": "1",
            "LIBGL_ALWAYS_SOFTWARE": "1", "QT_QPA_PLATFORM": "xcb", "SDL_VIDEODRIVER": "x11",
            "LCODE_SIMULATOR": "1",
            "LCODE_DEVICE_ID": str(device.get("id", "")), "LCODE_DEVICE_NAME": str(device.get("name", "")),
        })
        with self.lock:
            self.stop_app()
            self.app = Proc([exe], cwd, env, on_text, on_exit)
            return self.app

    def stop_app(self) -> None:
        with self.lock:
            if self.app:
                self.app.stop()
                self.app = None

    def _kill_server(self) -> None:
        if self.xvfb:
            self.xvfb.terminate()
            try:
                self.xvfb.wait(3)
            except subprocess.TimeoutExpired:
                self.xvfb.kill()
            self.xvfb = None

    def shutdown(self) -> None:
        with self.lock:
            self.stop_app()
            if self.agent:
                try:
                    self.agent.stdin.close()
                except OSError:
                    pass
                try:
                    self.agent.wait(2)
                except subprocess.TimeoutExpired:
                    self.agent.kill()
                self.agent = None
            self._kill_server()
            shutil.rmtree(self.frame_dir, ignore_errors=True)
            if self.power != "off":
                self._set_power("off")


# -------------------------------------------------------------------- tasks

class Tasks:
    """Build, test, clean and run: one at a time, as in Xcode."""

    def __init__(self, sim: Simulator) -> None:
        self.sim = sim
        self.lock = threading.Lock()
        self.gen = 0
        self.proc: Proc | None = None
        self.kind = ""
        self.cancelled = False
        self.in_simulator = False

    def stop(self) -> None:
        with self.lock:
            self.cancelled = True
            if self.proc:
                self.proc.stop()
            if self.in_simulator:
                self.sim.stop_app()

    def _begin(self, kind: str, title: str) -> int:
        self.stop()
        with self.lock:
            self.gen += 1
            self.kind, self.cancelled, self.in_simulator, self.proc = kind, False, False, None
            gen = self.gen
        emit({"event": "task.started", "gen": gen, "kind": kind, "title": title})
        return gen

    def tool(self, kind: str, root: str, args: list[str], title: str, then=None) -> int:
        swift = swift_executable()
        if not swift:
            raise RuntimeError("Swift toolchain not found. Install one (for example yay -S swift-bin) "
                               "or set its location in LCode Settings.")
        gen = self._begin(kind, title)
        counts = {"error": 0, "warning": 0}
        pending = {"text": ""}
        seen: set[tuple] = set()

        def on_text(_stream: str, text: str) -> None:
            emit({"event": "task.log", "gen": gen, "text": proj.strip_ansi(text)})
            pending["text"] += text
            *lines, pending["text"] = pending["text"].split("\n")
            for line in lines:
                handle(line)

        def handle(line: str) -> None:
            issue = proj.parse_diagnostic(line, root)
            if issue and issue["severity"] in counts:
                key = (issue["severity"], issue["message"], issue["path"], issue["line"])
                if key not in seen:
                    seen.add(key)
                    counts[issue["severity"]] += 1
                    emit({"event": "task.issue", "gen": gen, **issue})
            progress = proj.parse_progress(line)
            if progress:
                emit({"event": "task.progress", "gen": gen, **progress})

        def on_exit(code: int | None) -> None:
            if pending["text"]:
                handle(pending["text"])
            with self.lock:
                cancelled = self.cancelled and self.gen == gen
                if self.gen == gen:
                    self.proc = None
            if code not in (0, None) and not cancelled and counts["error"] == 0:
                counts["error"] += 1
                emit({"event": "task.issue", "gen": gen, "severity": "error", "path": "", "line": 0, "column": 0,
                      "message": f"Command failed with exit code {code}. See the log in the Report navigator."})
            emit({"event": "task.finished", "gen": gen, "kind": kind, "code": code, "cancelled": cancelled,
                  "errors": counts["error"], "warnings": counts["warning"]})
            if then and code == 0 and counts["error"] == 0 and not cancelled:
                with self.lock:
                    current = self.gen == gen
                if current:
                    threading.Thread(target=then, args=(gen,), daemon=True).start()

        try:
            proc = Proc([swift, *args], root, None, on_text, on_exit)
        except OSError as exc:
            emit({"event": "task.finished", "gen": gen, "kind": kind, "code": None, "cancelled": False,
                  "errors": 1, "warnings": 0, "error": str(exc)})
            raise RuntimeError(f"Couldn't run {swift}: {exc}") from exc
        with self.lock:
            if self.gen == gen:
                self.proc = proc
        return gen

    def run(self, root: str, product: str, destination: str, device: dict) -> int:
        def launch(gen: int) -> None:
            self.launch(gen, root, product, destination, device)
        return self.tool("build", root, ["build", "--product", product], f"Build {product}", then=launch)

    def launch(self, gen: int, root: str, product: str, destination: str, device: dict) -> None:
        exe = os.path.join(root, ".build", "debug", product)
        if not os.path.isfile(exe):
            emit({"event": "run.exited", "gen": gen, "code": None, "error": f"The built product wasn't found at {exe}."})
            return
        with self.lock:
            if self.gen != gen:
                return
            self.kind = "run"

        def on_text(stream: str, text: str) -> None:
            emit({"event": "run.output", "gen": gen, "stream": stream, "text": text})

        def on_exit(code: int | None) -> None:
            with self.lock:
                if self.gen == gen:
                    self.proc = None
            emit({"event": "run.exited", "gen": gen, "code": code})

        emit({"event": "run.started", "gen": gen, "product": product, "destination": destination})
        try:
            if destination == proj.HOST:
                proc = Proc([exe], root, None, on_text, on_exit)
            else:
                self.sim.boot(int(device["side"]), int(device["w"]), int(device["h"]))
                with self.lock:
                    self.in_simulator = True
                proc = self.sim.launch(exe, root, device, on_text, on_exit)
        except (OSError, RuntimeError, KeyError, ValueError) as exc:
            emit({"event": "run.exited", "gen": gen, "code": None, "error": str(exc)})
            return
        with self.lock:
            current = self.gen == gen
            if current and not self.cancelled:
                self.proc = proc if destination == proj.HOST else None
                return
        # Stopped (or replaced) while the program was starting. A replacing
        # Simulator run swaps the app itself, so only a host program is ours to end.
        if destination == proj.HOST:
            proc.stop()
        elif current:
            self.sim.stop_app()

    def relaunch(self, root: str, product: str, destination: str, device: dict) -> int:
        """Launch an already-built product (the Simulator's home screen)."""
        gen = self._begin("run", f"Run {product}")
        threading.Thread(target=self.launch, args=(gen, root, product, destination, device), daemon=True).start()
        return gen

    def stdin(self, text: str) -> None:
        with self.lock:
            proc = self.proc
        if proc and self.kind == "run":
            proc.write(text)
        elif self.in_simulator and self.sim.app:
            self.sim.app.write(text)


# ------------------------------------------------------------------- server

class Server:
    def __init__(self) -> None:
        self.sim = Simulator()
        self.tasks = Tasks(self.sim)
        self.root = ""
        self.watching = threading.Event()
        threading.Thread(target=self._watch, daemon=True).start()

    def _watch(self) -> None:
        signature = None
        while True:
            time.sleep(1.5)
            if not self.root:
                continue
            current = proj.tree_signature(self.root)
            if signature is not None and current != signature:
                emit({"event": "tree.changed"})
            signature = current

    # Each handler returns the reply payload or raises.
    def c_hello(self, _req: dict) -> dict:
        swift = swift_executable()
        return {"settings": load_settings(), "swift": swift or "", "swiftVersion": swift_version(swift),
                "xvfb": bool(shutil.which("Xvfb"))}

    def c_settings(self, req: dict) -> dict:
        data = load_settings()
        for k, v in (req.get("values") or {}).items():
            if k in DEFAULTS and k != "recent":
                data[k] = v
        save_settings(data)
        swift = swift_executable()
        return {"settings": data, "swift": swift or "", "swiftVersion": swift_version(swift)}

    def c_recent(self, req: dict) -> dict:
        data = load_settings()
        path = req.get("path", "")
        recent = [p for p in data["recent"] if p != path]
        if req.get("action") == "add" and path:
            recent.insert(0, path)
        data["recent"] = recent[:12]
        save_settings(data)
        return {"recent": data["recent"]}

    def c_open(self, req: dict) -> dict:
        project = proj.open_project(req["path"], load_settings().get("defaultSimulator", "lphone-16"))
        self.root = project["root"]
        self.c_recent({"action": "add", "path": self.root})
        return {"project": project}

    def c_projectInfo(self, _req: dict) -> dict:
        return {"project": proj.open_project(self.root, load_settings().get("defaultSimulator", "lphone-16"))}

    def c_saveState(self, req: dict) -> dict:
        proj.save_state(self.root, req.get("state") or {})
        return {}

    def c_saveMeta(self, req: dict) -> dict:
        proj.save_meta(self.root, req.get("kind", "tool"), req.get("bundleId", ""))
        return {}

    def c_tree(self, _req: dict) -> dict:
        return {"nodes": proj.tree(self.root)}

    def c_files(self, _req: dict) -> dict:
        return {"files": proj.files(self.root)}

    def c_read(self, req: dict) -> dict:
        path = req["path"]
        if os.path.getsize(path) > 8 * 1024 * 1024:
            raise ValueError(f"“{os.path.basename(path)}” is too large to edit.")
        raw = pathlib.Path(path).read_bytes()
        if b"\0" in raw[:8000]:
            raise ValueError(f"“{os.path.basename(path)}” is a binary file.")
        try:
            return {"text": raw.decode("utf-8"), "readOnly": False}
        except UnicodeDecodeError:
            return {"text": raw.decode("utf-8", "replace"), "readOnly": True}

    def c_write(self, req: dict) -> dict:
        path = pathlib.Path(req["path"])
        tmp = path.with_name(f".{path.name}.lcode-tmp")
        tmp.write_text(req.get("text", ""), encoding="utf-8")
        if path.exists():
            shutil.copymode(path, tmp)
        os.replace(tmp, path)
        return {}

    def c_newFile(self, req: dict) -> dict:
        folder, name = pathlib.Path(req["dir"]), req["name"].strip()
        if not name or "/" in name:
            raise ValueError("Enter a file name.")
        path = folder / name
        if path.exists():
            raise FileExistsError(f"“{name}” already exists.")
        meta = proj.open_project(self.root) if self.root else {"name": "", "organization": ""}
        if req.get("folder"):
            path.mkdir(parents=True)
        else:
            path.write_text(proj.new_file_contents(name, meta["name"], meta.get("organization", "")), encoding="utf-8")
        return {"path": str(path)}

    def c_rename(self, req: dict) -> dict:
        path = pathlib.Path(req["path"])
        name = req["name"].strip()
        if not name or "/" in name:
            raise ValueError("Enter a name.")
        target = path.with_name(name)
        if target.exists():
            raise FileExistsError(f"“{name}” already exists.")
        path.rename(target)
        return {"path": str(target)}

    def c_trash(self, req: dict) -> dict:
        p = subprocess.run(["gio", "trash", req["path"]], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        if p.returncode:
            raise OSError(p.stdout.strip() or "Couldn't move the item to the Trash.")
        return {}

    def c_find(self, req: dict) -> dict:
        return {"results": proj.find(self.root, req.get("query", ""), bool(req.get("caseSensitive")))}

    def c_create(self, req: dict) -> dict:
        settings = load_settings()
        settings["organizationName"] = req.get("organization", "")
        settings["organizationIdentifier"] = req.get("organizationId", "")
        save_settings(settings)
        root = proj.create_project(req["parent"], req["template"], req["name"], req.get("organization", ""),
                                   req.get("organizationId", ""), bool(req.get("tests", True)), bool(req.get("git", True)),
                                   settings.get("defaultSimulator", "lphone-16"))
        return {"root": root}

    def c_clone(self, req: dict) -> dict:
        url, parent = req["url"].strip(), req["parent"]
        name = url.rstrip("/").rsplit("/", 1)[-1].removesuffix(".git") or "repository"
        target = os.path.join(parent, name)
        p = subprocess.run(["git", "clone", "--", url, target], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        if p.returncode:
            raise RuntimeError(p.stdout.strip().splitlines()[-1] if p.stdout.strip() else "git clone failed.")
        return {"root": target}

    def c_build(self, req: dict) -> dict:
        product = req.get("product") or ""
        args = ["build", "--product", product] if product else ["build"]
        return {"gen": self.tasks.tool("build", self.root, args, f"Build {product or 'Package'}")}

    def c_test(self, _req: dict) -> dict:
        return {"gen": self.tasks.tool("test", self.root, ["test"], "Test")}

    def c_clean(self, _req: dict) -> dict:
        return {"gen": self.tasks.tool("clean", self.root, ["package", "clean"], "Clean Build Folder")}

    def c_run(self, req: dict) -> dict:
        return {"gen": self.tasks.run(self.root, req["product"], req["destination"], req.get("device") or {})}

    def c_launch(self, req: dict) -> dict:
        return {"gen": self.tasks.relaunch(self.root, req["product"], req["destination"], req.get("device") or {})}

    def c_dirs(self, req: dict) -> dict:
        """Folders inside a folder, for the location browser."""
        path = pathlib.Path(os.path.expanduser(req.get("path") or "~")).resolve()
        if not path.is_dir():
            raise FileNotFoundError(f"“{path}” is not a folder.")
        dirs = []
        for e in sorted(os.scandir(path), key=lambda e: e.name.lower()):
            if e.name.startswith(".") or not e.is_dir():
                continue
            dirs.append({"name": e.name, "path": e.path, "isProject": os.path.isfile(os.path.join(e.path, "Package.swift"))})
        home = pathlib.Path.home()
        places = [{"name": n, "path": str(home / d)} for n, d in
                  (("Home", ""), ("Developer", "Developer"), ("Documents", "Documents"), ("Desktop", "Desktop"))
                  if (home / d).is_dir()]
        return {"path": str(path), "parent": str(path.parent), "dirs": dirs, "places": places,
                "isProject": (path / "Package.swift").is_file()}

    def c_mkdir(self, req: dict) -> dict:
        path = pathlib.Path(os.path.expanduser(req["path"]))
        path.mkdir(parents=True, exist_ok=True)
        return {"path": str(path)}

    def c_stop(self, _req: dict) -> dict:
        self.tasks.stop()
        return {}

    def c_stdin(self, req: dict) -> dict:
        self.tasks.stdin(req.get("text", ""))
        return {}

    def c_simBoot(self, req: dict) -> dict:
        threading.Thread(target=self._boot, args=(req,), daemon=True).start()
        return {}

    def _boot(self, req: dict) -> None:
        try:
            self.sim.boot(int(req["side"]), int(req["w"]), int(req["h"]))
        except (RuntimeError, OSError):
            pass  # reported through sim.state

    def c_simShutdown(self, _req: dict) -> dict:
        self.sim.shutdown()
        return {}

    def c_simRegion(self, req: dict) -> dict:
        self.sim.region(int(req["w"]), int(req["h"]))
        return {}

    def c_simInput(self, req: dict) -> dict:
        self.sim.input(req.get("input") or {})
        return {}

    def c_simStopApp(self, _req: dict) -> dict:
        self.sim.stop_app()
        return {}

    def handle(self, req: dict) -> None:
        rid = req.get("id")
        handler = getattr(self, "c_" + str(req.get("cmd")), None)
        try:
            if handler is None:
                raise ValueError(f"Unknown command {req.get('cmd')!r}")
            reply = {"ok": True, **handler(req)}
        except (OSError, ValueError, RuntimeError, KeyError, FileExistsError) as exc:
            reply = {"ok": False, "error": str(exc) or exc.__class__.__name__}
        if rid is not None:
            emit({"id": rid, **reply})

    def serve(self) -> int:
        # Quick requests answer inline; slow ones run off the reading thread so
        # input (Simulator touches) is never stuck behind them.
        slow = {"find", "create", "clone", "tree", "hello", "settings", "dirs", "files"}
        try:
            for line in sys.stdin:
                line = line.strip()
                if not line:
                    continue
                try:
                    req = json.loads(line)
                except ValueError:
                    continue
                if req.get("cmd") in slow:
                    threading.Thread(target=self.handle, args=(req,), daemon=True).start()
                else:
                    self.handle(req)
        finally:
            self.tasks.stop()
            self.sim.shutdown()
        return 0


def main(argv: list[str]) -> int:
    if len(argv) >= 2 and argv[1] == "serve":
        return Server().serve()
    try:
        if len(argv) >= 5 and argv[1] == "create":
            root = proj.create_project(argv[2], argv[3], argv[4], org_id=argv[5] if len(argv) > 5 else "", git=False)
            print(json.dumps({"ok": True, "root": root}))
            return 0
        if len(argv) == 3 and argv[1] == "project":
            print(json.dumps({"ok": True, "project": proj.open_project(argv[2])}))
            return 0
        if len(argv) == 3 and argv[1] == "diagnostics":
            issues = [d for d in (proj.parse_diagnostic(l, argv[2]) for l in sys.stdin) if d]
            print(json.dumps({"ok": True, "issues": issues}))
            return 0
    except (OSError, ValueError) as exc:
        print(json.dumps({"ok": False, "error": str(exc)}))
        return 1
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
