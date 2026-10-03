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
import lcode_toolchains as toolchains  # noqa: E402
import lcode_design as design  # noqa: E402
import lcode_icon as icons  # noqa: E402
import lcode_archive as archive  # noqa: E402

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
    "pythonPath": "",
    "cargoPath": "",
    "mesonPath": "",
    "qsPath": "",
    "fontSize": 13,
    "tabWidth": 4,
    "showMinimap": True,
    "showWelcome": True,
    "defaultSimulator": "lphone-16",
    "organizationName": "",
    "organizationIdentifier": "com.example",
    "projectsFolder": "",
    "reopenFiles": True,
    # Settings ▸ General, Themes and Text Editing.
    "appearance": "system",             # system | light | dark
    "editorThemeLight": "default-light",
    "editorThemeDark": "default-dark",
    "customThemes": [],
    "fontFamily": "monospace",
    "showLineNumbers": True,
    "highlightCurrentLine": True,
    "autoClose": True,
    "insertSpaces": True,
    "trimWhitespace": True,
    "ensureNewline": True,
    "codeCompletion": True,
    # Settings ▸ Key Bindings, Behaviors and Simulators.
    "keyBindings": {},
    "behaviors": {},
    "customDevices": [],
    "userSnippets": [],                 # Library ▸ Snippets: your own
    "recent": [],
}


def valid_setting(key: str, value) -> bool:
    """A value of the default's type (any number for a number)."""
    default = DEFAULTS[key]
    if isinstance(default, bool):
        return isinstance(value, bool)
    if isinstance(default, (int, float)):
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    return isinstance(value, type(default))


def load_settings() -> dict:
    data = dict(DEFAULTS)
    data.update(proj.read_json(config_path()))
    data["recent"] = [p for p in data.get("recent", []) if isinstance(p, str) and os.path.isdir(p)]
    return data


def save_settings(data: dict) -> None:
    proj.write_json(config_path(), data)


def toolchain_report(settings: dict) -> dict:
    """Which toolchains are installed: {id: {path, version, hint}}."""
    out = {}
    for t in toolchains.IDS:
        path = toolchains.executable(t, settings)
        if path and not os.path.isabs(path):
            path = shutil.which(path) or path
        if path and not (os.path.isfile(path) and os.access(path, os.X_OK)):
            path = None
        out[t] = {"path": path or "", "version": toolchains.version(t, path) if path else "",
                  "hint": toolchains.install_hint(t), "name": toolchains.NAMES[t]}
    return out


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

    def launch(self, argv: list[str], cwd: str, device: dict, on_text, on_exit, extra_env: dict | None = None) -> Proc:
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
        env.update(extra_env or {})
        with self.lock:
            self.stop_app()
            self.app = Proc(argv, cwd, env, on_text, on_exit)
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

    def tool(self, kind: str, root: str, toolchain: str, product: str, title: str, then=None,
             configuration: str = "debug") -> int:
        settings = load_settings()
        exe = toolchains.executable(toolchain, settings) if toolchain else None
        needs_exe = toolchain in ("swift", "cargo", "meson", "python")
        if needs_exe and not exe:
            name = toolchains.NAMES[toolchain]
            raise RuntimeError(f"No {name} toolchain was found. Install it ({toolchains.install_hint(toolchain)}) "
                               "or set its location in LCode Settings ▸ Locations.")
        plan = toolchains.steps(toolchain, kind, root, product, exe or "", settings, configuration)
        gen = self._begin(kind, title)
        counts = {"error": 0, "warning": 0}
        seen: set[tuple] = set()

        def start(index: int) -> None:
            argv, cwd, diag_root = plan[index]
            pending = {"text": ""}

            def handle(line: str) -> None:
                issue = toolchains.parse_diagnostic(line, diag_root)
                if issue and issue["severity"] in counts:
                    key = (issue["severity"], issue["message"], issue["path"], issue["line"])
                    if key not in seen:
                        seen.add(key)
                        counts[issue["severity"]] += 1
                        emit({"event": "task.issue", "gen": gen, **issue})
                progress = toolchains.parse_progress(line)
                if progress:
                    emit({"event": "task.progress", "gen": gen, **progress})

            def on_text(_stream: str, text: str) -> None:
                emit({"event": "task.log", "gen": gen, "text": toolchains.strip_ansi(text)})
                pending["text"] += text
                *lines, pending["text"] = pending["text"].split("\n")
                for line in lines:
                    handle(line)

            def on_exit(code: int | None) -> None:
                if pending["text"]:
                    handle(pending["text"])
                with self.lock:
                    cancelled = self.cancelled and self.gen == gen
                    current = self.gen == gen
                    if current:
                        self.proc = None
                if code == 0 and not cancelled and current and index + 1 < len(plan):
                    try:
                        start(index + 1)
                    except RuntimeError as exc:
                        emit({"event": "task.log", "gen": gen, "text": str(exc) + "\n"})
                        finish(None, False)
                    return
                finish(code, cancelled)

            emit({"event": "task.log", "gen": gen, "text": "$ " + " ".join(argv) + "\n"})
            try:
                proc = Proc(argv, cwd, None, on_text, on_exit)
            except OSError as exc:
                raise RuntimeError(f"Couldn't run {argv[0]}: {exc}") from exc
            with self.lock:
                if self.gen == gen:
                    self.proc = proc

        def finish(code: int | None, cancelled: bool) -> None:
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
            start(0)
        except RuntimeError as exc:
            emit({"event": "task.finished", "gen": gen, "kind": kind, "code": None, "cancelled": False,
                  "errors": 1, "warnings": 0, "error": str(exc)})
            raise
        return gen

    def run(self, root: str, toolchain: str, product: str, destination: str, device: dict, scheme: dict) -> int:
        def launch(gen: int) -> None:
            self.launch(gen, root, toolchain, product, destination, device, scheme)
        return self.tool("build", root, toolchain, product, f"Build {product}", then=launch,
                         configuration=scheme.get("configuration") or "debug")

    def launch(self, gen: int, root: str, toolchain: str, product: str, destination: str, device: dict,
               scheme: dict) -> None:
        configuration = scheme.get("configuration") or "debug"
        try:
            argv = toolchains.program(toolchain, root, product, load_settings(), configuration)
        except RuntimeError as exc:
            emit({"event": "run.exited", "gen": gen, "code": None, "error": str(exc)})
            return
        if toolchain in ("swift", "cargo", "meson") and not os.path.isfile(argv[0]):
            emit({"event": "run.exited", "gen": gen, "code": None, "error": f"The built product wasn't found at {argv[0]}."})
            return
        argv = argv + [str(a) for a in (scheme.get("arguments") or []) if str(a)]
        extra_env = {str(k): str(v) for k, v in (scheme.get("environment") or {}).items() if str(k)}
        cwd = scheme.get("workingDirectory") or root
        with self.lock:
            if self.gen != gen:
                return
            self.kind = "run"
        runtime = toolchains.RuntimeIssues(root) if toolchain == "python" else None

        def on_text(stream: str, text: str) -> None:
            emit({"event": "run.output", "gen": gen, "stream": stream, "text": text})
            if runtime and stream == "stderr":
                for issue in runtime.feed(text):
                    emit({"event": "task.issue", "gen": gen, **issue})

        def on_exit(code: int | None) -> None:
            with self.lock:
                if self.gen == gen:
                    self.proc = None
            emit({"event": "run.exited", "gen": gen, "code": code})

        emit({"event": "run.started", "gen": gen, "product": product, "destination": destination})
        try:
            if destination == proj.HOST:
                env = dict(os.environ, **extra_env) if extra_env else None
                proc = Proc(argv, cwd, env, on_text, on_exit)
            else:
                self.sim.boot(int(device["side"]), int(device["w"]), int(device["h"]))
                with self.lock:
                    self.in_simulator = True
                proc = self.sim.launch(argv, cwd, device, on_text, on_exit, extra_env)
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

    def relaunch(self, root: str, toolchain: str, product: str, destination: str, device: dict, scheme: dict) -> int:
        """Launch an already-built product (the Simulator's home screen)."""
        gen = self._begin("run", f"Run {product}")
        threading.Thread(target=self.launch, args=(gen, root, toolchain, product, destination, device, scheme),
                         daemon=True).start()
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
        settings = load_settings()
        return {"settings": settings, "toolchains": toolchain_report(settings), "xvfb": bool(shutil.which("Xvfb"))}

    def c_settings(self, req: dict) -> dict:
        data = load_settings()
        for k, v in (req.get("values") or {}).items():
            if k in DEFAULTS and k != "recent" and valid_setting(k, v):
                data[k] = v
        save_settings(data)
        return {"settings": data, "toolchains": toolchain_report(data)}

    GIT_KEYS = {"name": "user.name", "email": "user.email", "defaultBranch": "init.defaultBranch"}

    def c_gitIdentity(self, req: dict) -> dict:
        """Settings ▸ Accounts: your name and email for commits (git config --global)."""
        if not shutil.which("git"):
            return {"installed": False, "identity": {}}
        for key, value in (req.get("values") or {}).items():
            if key not in self.GIT_KEYS or not isinstance(value, str):
                continue
            value = value.strip()
            args = ["git", "config", "--global"] + (["--unset", self.GIT_KEYS[key]] if not value else [self.GIT_KEYS[key], value])
            subprocess.run(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        identity = {}
        for key, name in self.GIT_KEYS.items():
            p = subprocess.run(["git", "config", "--global", "--get", name], stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL, text=True)
            identity[key] = p.stdout.strip()
        return {"installed": True, "identity": identity}

    def c_fonts(self, _req: dict) -> dict:
        """Monospaced font families, for Settings ▸ Text Editing."""
        families = []
        if shutil.which("fc-list"):
            p = subprocess.run(["fc-list", ":spacing=mono", "family"], stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL, text=True)
            for line in p.stdout.splitlines():
                name = line.split(",")[0].strip()
                if name and name not in families:
                    families.append(name)
        return {"families": sorted(families, key=str.lower)}

    def c_recent(self, req: dict) -> dict:
        data = load_settings()
        path = req.get("path", "")
        recent = [p for p in data["recent"] if p != path]
        if req.get("action") == "add" and path:
            recent.insert(0, path)
        data["recent"] = recent[:12]
        save_settings(data)
        return {"recent": data["recent"]}

    def project(self) -> dict:
        if not self.root:
            raise ValueError("No project is open.")
        return proj.open_project(self.root, load_settings().get("defaultSimulator", "lphone-16"))

    def scheme(self, req: dict) -> dict:
        """Run options: the project's scheme (.lcode/project.json) unless the request has its own."""
        scheme = dict(self.project()["meta"].get("scheme") or {})
        scheme.update(req.get("scheme") or {})
        return scheme

    def c_open(self, req: dict) -> dict:
        project = proj.open_project(req["path"], load_settings().get("defaultSimulator", "lphone-16"))
        self.root = project["root"]
        self.c_recent({"action": "add", "path": self.root})
        return {"project": project}

    def c_projectInfo(self, _req: dict) -> dict:
        return {"project": self.project()}

    def c_saveState(self, req: dict) -> dict:
        proj.save_state(self.root, req.get("state") or {})
        return {}

    def c_saveMeta(self, req: dict) -> dict:
        values = dict(req.get("values") or {})
        if "kind" in req:
            values["kind"] = req["kind"]
        if "bundleId" in req:
            values["bundle_identifier"] = req["bundleId"]
        return {"meta": proj.save_meta(self.root, values)}

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
                                   settings.get("defaultSimulator", "lphone-16"), req.get("options") or {})
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
        p = self.project()
        product = req.get("product") or ""
        configuration = req.get("configuration") or self.scheme(req).get("configuration") or "debug"
        return {"gen": self.tasks.tool("build", self.root, p["toolchain"], product, f"Build {product or p['name']}",
                                       configuration=configuration)}

    def c_test(self, _req: dict) -> dict:
        p = self.project()
        return {"gen": self.tasks.tool("test", self.root, p["toolchain"], "", "Test")}

    def c_clean(self, _req: dict) -> dict:
        p = self.project()
        return {"gen": self.tasks.tool("clean", self.root, p["toolchain"], "", "Clean Build Folder")}

    def c_archive(self, req: dict) -> dict:
        p = self.project()
        product = req.get("product") or (p["products"][0] if p["products"] else "")
        return {"gen": self.tasks.tool("archive", self.root, p["toolchain"], product, f"Archive {p['displayName'] or p['name']}")}

    def c_archiveInfo(self, _req: dict) -> dict:
        return archive.archive_summary(self.root)

    def c_distribute(self, req: dict) -> dict:
        """Install the archive, or export it (pkgbuild, flatpak, tarball); uninstall."""
        method = req.get("method")
        log = []
        if method == "install":
            r = archive.install(self.root, req.get("prefix") or None, out=log.append)
        elif method == "uninstall":
            r = archive.uninstall(archive.Info(self.root).app_id, out=log.append)
        elif method in ("pkgbuild", "flatpak", "tarball"):
            r = getattr(archive, method)(self.root, out=log.append)
        else:
            raise ValueError(f"Unknown way to distribute: {method!r}")
        return {**r, "log": "\n".join(log), "info": archive.archive_summary(self.root)}

    def c_run(self, req: dict) -> dict:
        p = self.project()
        return {"gen": self.tasks.run(self.root, p["toolchain"], req["product"], req["destination"],
                                      req.get("device") or {}, self.scheme(req))}

    def c_launch(self, req: dict) -> dict:
        p = self.project()
        return {"gen": self.tasks.relaunch(self.root, p["toolchain"], req["product"], req["destination"],
                                           req.get("device") or {}, self.scheme(req))}

    # ---------------------------------------------------------- designer
    def c_designCode(self, req: dict) -> dict:
        """The QML a design (as edited, maybe unsaved) generates for one screen, or the app."""
        doc = json.loads(req["text"])
        gen = design.Gen(doc)
        if req.get("screen") == "@app":
            meta = self.project()["meta"] if self.root else {}
            return {"code": gen.app(meta.get("bundle_identifier") or "org.example.App", True)}
        screen = next((s for s in doc.get("screens") or [] if s.get("id") == req.get("screen")), None)
        if not screen:
            raise ValueError("No such screen.")
        return {"code": gen.screen(screen)}

    def c_iconPreview(self, req: dict) -> dict:
        """Draw the project's icon (or one being edited) for the project editor."""
        meta = self.project()["meta"]
        icon = req.get("icon") or meta.get("icon") or icons.default_icon(self.project()["toolchain"], meta.get("accent") or "#0a84ff")
        light, dark = icons.write(icon, pathlib.Path(self.root) / ".lcode/userdata", "icon-preview", pathlib.Path(self.root))
        return {"light": str(light), "dark": str(dark), "icon": icon}

    def c_symbols(self, _req: dict) -> dict:
        folder = design.UI / "assets" / "symbols"
        names = sorted({p.stem for p in folder.glob("*.svg") if "@" not in p.stem})
        return {"symbols": names}

    IMAGE_TYPES = (".png", ".jpg", ".jpeg", ".svg", ".webp", ".gif")

    def c_assets(self, _req: dict) -> dict:
        root = pathlib.Path(self.root)
        folder = root / "Assets"
        out = []
        if folder.is_dir():
            for p in sorted(folder.rglob("*")):
                if p.is_file() and p.suffix.lower() in self.IMAGE_TYPES:
                    out.append(str(p.relative_to(root)))
        return {"assets": out}

    def c_importAsset(self, req: dict) -> dict:
        src = pathlib.Path(os.path.expanduser(req["path"].strip()))
        if not src.is_file():
            raise FileNotFoundError(f"“{src}” isn't a file.")
        if src.suffix.lower() not in self.IMAGE_TYPES:
            raise ValueError("Choose a PNG, JPEG, SVG, WebP or GIF image.")
        folder = pathlib.Path(self.root) / "Assets"
        folder.mkdir(exist_ok=True)
        target = folder / src.name
        n = 2
        while target.exists() and not target.samefile(src):
            target = folder / f"{src.stem}-{n}{src.suffix}"
            n += 1
        if not target.exists():
            shutil.copy2(src, target)
        return {"path": str(target.relative_to(self.root))}

    def c_dirs(self, req: dict) -> dict:
        """Folders inside a folder, for the location browser."""
        path = pathlib.Path(os.path.expanduser(req.get("path") or "~")).resolve()
        if not path.is_dir():
            raise FileNotFoundError(f"“{path}” is not a folder.")
        dirs = []
        for e in sorted(os.scandir(path), key=lambda e: e.name.lower()):
            if e.name.startswith(".") or not e.is_dir():
                continue
            dirs.append({"name": e.name, "path": e.path, "isProject": toolchains.is_project(e.path)})
        home = pathlib.Path.home()
        places = [{"name": n, "path": str(home / d)} for n, d in
                  (("Home", ""), ("Developer", "Developer"), ("Documents", "Documents"), ("Desktop", "Desktop"))
                  if (home / d).is_dir()]
        return {"path": str(path), "parent": str(path.parent), "dirs": dirs, "places": places,
                "isProject": toolchains.is_project(str(path))}

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
        except (OSError, ValueError, RuntimeError, KeyError, FileExistsError, TypeError) as exc:
            reply = {"ok": False, "error": str(exc) or exc.__class__.__name__}
        if rid is not None:
            emit({**reply, "id": rid})          # the request's id wins over any "id" in the reply

    def serve(self) -> int:
        # Quick requests answer inline; slow ones run off the reading thread so
        # input (Simulator touches) is never stuck behind them.
        slow = {"find", "create", "clone", "tree", "hello", "settings", "dirs", "files", "designCode", "symbols", "assets", "importAsset", "iconPreview", "distribute", "archiveInfo", "gitIdentity", "fonts"}
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
