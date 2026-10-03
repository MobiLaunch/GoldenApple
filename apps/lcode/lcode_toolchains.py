"""LCode toolchains: how each kind of project is recognised, built, tested,
cleaned and run, and how its tools report problems.

    swift        Package.swift            SwiftPM
    cargo        Cargo.toml               Rust (cargo)
    meson        meson.build              C / C++ (Meson + Ninja)
    python       pyproject.toml, main.py  Python (PyGObject for GTK apps)
    goldengate   Interface.lcdesign       Golden Gate apps designed in LCode (QML)

A step is (argv, cwd, diagnostics_root): diagnostics_root is the folder the
tool's relative paths start from (Ninja reports paths relative to build/).
"""
from __future__ import annotations

import os
import pathlib
import re
import shutil
import subprocess
import sys

try:
    import tomllib
except ImportError:  # Python < 3.11
    tomllib = None

HERE = pathlib.Path(__file__).resolve().parent
TOOL = str(HERE / "lcode_tool.py")

IDS = ("swift", "cargo", "meson", "python", "goldengate")
NAMES = {"swift": "Swift", "cargo": "Rust", "meson": "C", "python": "Python", "goldengate": "Golden Gate"}

# Settings key, executable name, how to install it on Golden Gate (Arch).
EXECUTABLES = {
    "swift": ("swiftPath", "swift", "yay -S swift-bin  (or install swiftly)"),
    "cargo": ("cargoPath", "cargo", "sudo pacman -S rust"),
    "meson": ("mesonPath", "meson", "sudo pacman -S meson gcc"),
    "python": ("pythonPath", "python3", "sudo pacman -S python python-gobject libadwaita"),
    "goldengate": ("qsPath", "qs", "sudo pacman -S quickshell"),
}
ENV_OVERRIDES = {"swift": "LCODE_SWIFT", "cargo": "LCODE_CARGO", "meson": "LCODE_MESON",
                 "python": "LCODE_PYTHON", "goldengate": "LCODE_QS"}


def executable(toolchain: str, settings: dict) -> str | None:
    key, name, _ = EXECUTABLES[toolchain]
    configured = (settings.get(key) or "").strip()
    if configured:
        return configured
    env = os.environ.get(ENV_OVERRIDES[toolchain])
    if env:
        return env
    return shutil.which(name)


def version(toolchain: str, path: str | None) -> str:
    if not path:
        return ""
    if toolchain == "goldengate":
        return "Quickshell"
    try:
        out = subprocess.run([path, "--version"], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        return ""
    first = out.stdout.strip().splitlines()[0] if out.returncode == 0 and out.stdout.strip() else ""
    if toolchain == "meson" and first and not first.lower().startswith("meson"):
        first = "Meson " + first
    return first


def install_hint(toolchain: str) -> str:
    return EXECUTABLES[toolchain][2]


# ------------------------------------------------------------- detection

def read(path: pathlib.Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return ""


def detect(root: pathlib.Path, meta: dict) -> str:
    chosen = meta.get("toolchain")
    if chosen in IDS:
        return chosen
    if (root / "Package.swift").is_file():
        return "swift"
    if (root / "Cargo.toml").is_file():
        return "cargo"
    if (root / "meson.build").is_file():
        return "meson"
    if (root / "Interface.lcdesign").is_file():
        return "goldengate"
    if (root / "pyproject.toml").is_file() or (root / "main.py").is_file() or (root / "setup.py").is_file():
        return "python"
    return ""


def is_project(path: str) -> bool:
    root = pathlib.Path(path)
    return any((root / marker).is_file() for marker in
               ("Package.swift", "Cargo.toml", "meson.build", "Interface.lcdesign", "pyproject.toml", "main.py"))


SWIFT_NAME = re.compile(r'Package\s*\(\s*name:\s*"([^"]+)"')
SWIFT_EXECUTABLES = re.compile(r'\.(?:executableTarget|executable)\s*\(\s*name:\s*"([^"]+)"')
SWIFT_GUI = ("swift-cross-ui", "SwiftCrossUI", "adwaita-swift", "Adwaita")
MESON_PROJECT = re.compile(r"project\s*\(\s*'([^']+)'")
MESON_EXECUTABLES = re.compile(r"executable\s*\(\s*'([^']+)'")
GUI_DEPENDENCIES = ("gtk4", "libadwaita", "gtk+-3.0", "gtk", "Gtk", "Adw", "gi.repository")


def unique(items) -> list[str]:
    out: list[str] = []
    for i in items:
        if i and i not in out:
            out.append(i)
    return out


def describe(toolchain: str, root: pathlib.Path) -> dict:
    """{name, products, kind} from the project's own build files."""
    if toolchain == "swift":
        text = read(root / "Package.swift")
        m = SWIFT_NAME.search(text)
        products = unique(m.group(1) for m in SWIFT_EXECUTABLES.finditer(text))
        kind = "app" if any(s in text for s in SWIFT_GUI) else "tool" if products or not text else "library"
        return {"name": m.group(1) if m else root.name, "products": products, "kind": kind}
    if toolchain == "cargo":
        data = {}
        if tomllib:
            try:
                data = tomllib.loads(read(root / "Cargo.toml"))
            except (ValueError, TypeError):
                data = {}
        package = data.get("package", {}) if isinstance(data.get("package"), dict) else {}
        name = package.get("name") or root.name
        bins = [b.get("name") for b in data.get("bin", []) if isinstance(b, dict)]
        if (root / "src/main.rs").is_file():
            bins.insert(0, name)
        deps = data.get("dependencies", {}) if isinstance(data.get("dependencies"), dict) else {}
        kind = "app" if any(d in deps for d in ("gtk4", "gtk", "libadwaita", "relm4", "iced", "egui", "eframe")) \
            else "tool" if bins else "library"
        return {"name": name, "products": unique(bins), "kind": kind}
    if toolchain == "meson":
        text = read(root / "meson.build")
        m = MESON_PROJECT.search(text)
        # Test programs aren't products you run.
        products = unique(m.group(1) for m in MESON_EXECUTABLES.finditer(text) if not m.group(1).startswith("test"))
        kind = "app" if any(f"'{d}'" in text for d in ("gtk4", "libadwaita-1", "gtk+-3.0")) else "tool" if products else "library"
        return {"name": m.group(1) if m else root.name, "products": products, "kind": kind}
    if toolchain == "python":
        name = root.name
        if tomllib and (root / "pyproject.toml").is_file():
            try:
                name = tomllib.loads(read(root / "pyproject.toml")).get("project", {}).get("name") or name
            except (ValueError, TypeError, AttributeError):
                pass
        main = python_main(root)
        sources = " ".join(read(p) for p in list(root.glob("*.py"))[:20] + list(root.glob("*/*.py"))[:40])
        kind = "app" if "gi.repository" in sources or "PySide6" in sources or "PyQt" in sources else "tool" if main else "library"
        return {"name": name, "products": [name] if main else [], "kind": kind}
    if toolchain == "goldengate":
        import lcode_design as design
        doc = design.load(root)
        return {"name": doc.get("app", {}).get("name") or root.name, "products": [doc.get("app", {}).get("name") or root.name],
                "kind": "app"}
    return {"name": root.name, "products": [], "kind": "folder"}


def python_main(root: pathlib.Path) -> str:
    for candidate in ("main.py", "__main__.py", "app.py", f"{root.name}.py"):
        if (root / candidate).is_file():
            return candidate
    return ""


# ----------------------------------------------------------------- tasks

class Missing(RuntimeError):
    pass


def steps(toolchain: str, action: str, root: str, product: str, exe: str, settings: dict,
          configuration: str = "debug") -> list[tuple[list[str], str, str]]:
    """The commands for build / test / clean, and archive (a release build, laid out to install)."""
    if action == "archive":
        return steps(toolchain, "build", root, product, exe, settings, "release") + \
            [([sys.executable, str(HERE / "lcode_archive.py"), "stage", root], root, root)]
    release = configuration == "release"
    if toolchain == "swift":
        if action == "build":
            args = ["build", "--product", product] if product else ["build"]
            # Release builds carry the Swift runtime with them, so they run anywhere.
            return [([exe, *args, *(["-c", "release", "--static-swift-stdlib"] if release else [])], root, root)]
        if action == "test":
            return [([exe, "test"], root, root)]
        return [([exe, "package", "clean"], root, root)]
    if toolchain == "cargo":
        if action == "build":
            args = ["build", "--message-format=short", *(["--release"] if release else [])]
            if product:
                args += ["--bin", product]
            return [([exe, *args], root, root)]
        if action == "test":
            return [([exe, "test", "--message-format=short"], root, root)]
        return [([exe, "clean"], root, root)]
    if toolchain == "meson":
        build = os.path.join(root, "build-release" if release else "build")
        configure = [] if os.path.isfile(os.path.join(build, "build.ninja")) else \
            [([exe, "setup", build, *(["--buildtype=release"] if release else [])], root, root)]
        if action == "build":
            return configure + [([exe, "compile", "-C", build], root, build)]
        if action == "test":
            return configure + [([exe, "test", "-C", build, "--print-errorlogs"], root, build)]
        return [([sys.executable, TOOL, "rmtree", os.path.join(root, "build"), os.path.join(root, "build-release")], root, root)]
    if toolchain == "python":
        if action == "build":
            return [([exe, TOOL, "check", root], root, root)]
        if action == "test":
            return [([exe, TOOL, "test", root], root, root)]
        return [([sys.executable, TOOL, "clean-python", root], root, root)]
    if toolchain == "goldengate":
        if action == "build":
            return [([sys.executable, str(HERE / "lcode_design.py"), "build", root, *(["--release"] if release else [])], root, root)]
        if action == "test":
            return [([sys.executable, str(HERE / "lcode_design.py"), "build", root, "--check"], root, root)]
        return [([sys.executable, TOOL, "rmtree", os.path.join(root, ".build")], root, root)]
    raise Missing("LCode doesn't know how to build this folder. Create a project with File ▸ New ▸ Project, "
                  "or add a Package.swift, Cargo.toml, meson.build or main.py.")


def program(toolchain: str, root: str, product: str, settings: dict, configuration: str = "debug") -> list[str]:
    """The built program to run, as argv."""
    if toolchain == "swift":
        return [os.path.join(root, ".build", configuration, product)]
    if toolchain == "cargo":
        return [os.path.join(root, "target", configuration, product)]
    if toolchain == "meson":
        return [os.path.join(root, "build-release" if configuration == "release" else "build", product)]
    if toolchain == "python":
        python = executable("python", settings) or "python3"
        return [python, os.path.join(root, python_main(pathlib.Path(root)) or "main.py")]
    if toolchain == "goldengate":
        qs = executable("goldengate", settings) or "qs"
        return [qs, "-n", "-p", os.path.join(root, ".build", "app", "App.qml")]
    raise Missing("Nothing to run.")


# ----------------------------------------------------------- diagnostics

LOCATED = re.compile(r"^(?P<path>[^:\s][^:]*):(?P<line>\d+):(?:(?P<col>\d+):)? "
                     r"(?:fatal )?(?P<sev>error|warning|note)(?:\[[\w-]+\])?: (?P<msg>.+)$")
GLOBAL = re.compile(r"^(?:\S+: )?(?P<sev>error|warning)(?:\[[\w-]+\])?: (?P<msg>.+)$")
PROGRESS = re.compile(r"^\[(?P<done>\d+)/(?P<total>\d+)\]\s*(?P<what>.*)$")
CARGO_PROGRESS = re.compile(r"^\s+(?P<what>Compiling|Checking|Downloaded|Downloading|Building|Linking|Finished|Running) (?P<rest>.+)$")
ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
# Summary lines that repeat what was already reported.
SUMMARIES = re.compile(r"^(could not compile|aborting due to|build failed|\d+ (warnings?|errors?) (emitted|generated))"
                       r"|generated \d+ warnings?|^`[^`]+` \(.*\) generated", re.I)


def strip_ansi(text: str) -> str:
    return ANSI.sub("", text)


def parse_diagnostic(line: str, root: str) -> dict | None:
    line = strip_ansi(line).rstrip()
    m = LOCATED.match(line)
    if m:
        path = m.group("path")
        if not os.path.isabs(path):
            path = os.path.join(root, path)
        return {"severity": m.group("sev"), "message": m.group("msg"), "path": os.path.normpath(path),
                "line": int(m.group("line")), "column": int(m.group("col") or 1)}
    m = GLOBAL.match(line)
    if m and not SUMMARIES.search(m.group("msg")):
        return {"severity": m.group("sev"), "message": m.group("msg"), "path": "", "line": 0, "column": 0}
    return None


def parse_progress(line: str) -> dict | None:
    line = strip_ansi(line).rstrip()
    m = PROGRESS.match(line)
    if m:
        return {"done": int(m.group("done")), "total": int(m.group("total")), "message": m.group("what").strip()}
    m = CARGO_PROGRESS.match(line)
    if m:
        rest = m.group("rest").split(" (")[0]
        return {"done": 0, "total": 0, "message": f"{m.group('what')} {rest}"}
    return None


class RuntimeIssues:
    """Turns a Python traceback in a running program's output into an issue
    at the innermost line of the project's own code."""

    FRAME = re.compile(r'^\s*File "(?P<path>[^"]+)", line (?P<line>\d+)')
    EXCEPTION = re.compile(r"^(?P<name>[A-Za-z_][\w.]*(?:Error|Exception|Exit|Interrupt|Warning)|[A-Za-z_]\w*Error)(?:: (?P<msg>.*))?$")

    def __init__(self, root: str) -> None:
        self.root = os.path.realpath(root)
        self.frame: tuple[str, int] | None = None
        self.in_traceback = False
        self.pending = ""

    def feed(self, text: str) -> list[dict]:
        out = []
        self.pending += text
        *lines, self.pending = self.pending.split("\n")
        for line in lines:
            issue = self.line(line)
            if issue:
                out.append(issue)
        return out

    def line(self, line: str) -> dict | None:
        line = strip_ansi(line.rstrip())
        if line.startswith("Traceback (most recent call last)"):
            self.in_traceback, self.frame = True, None
            return None
        if not self.in_traceback:
            return None
        m = self.FRAME.match(line)
        if m:
            path = os.path.realpath(m.group("path"))
            if path.startswith(self.root + os.sep):
                self.frame = (path, int(m.group("line")))
            return None
        m = self.EXCEPTION.match(line)
        if m:
            self.in_traceback = False
            path, number = self.frame or ("", 0)
            message = m.group("name") + (": " + m.group("msg") if m.group("msg") else "")
            return {"severity": "error", "runtime": True, "message": message, "path": path, "line": number, "column": 1}
        return None
