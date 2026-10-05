#!/usr/bin/env python3
"""CitronOS UI preview: renders the shell, or an app, to a PNG without
Quickshell or Hyprland, for design review and before/after comparisons.

Quickshell's modules are stood in for by tools/preview/qml (and the Wayland
types below): every window is drawn into one scene, stacked by layer like
Hyprland stacks them, over the wallpaper, with the backdrop blurred behind
glass surfaces and app windows as HyprGlass does. Commands answer from
FIXTURES, so surfaces show what they would on a typical machine.

    preview.py shell [--dark] [--do controlcenter.toggle] [--notify] -o out.png
    preview.py app apps/settings.qml [--dark] [--env GG_SETTINGS_PANE=general] -o out.png

--do calls an IpcHandler function, as `qs ipc call` would (target.function,
arguments after colons: controlcenter.detail:wifi). Repeatable; run in order.
"""
from __future__ import annotations

import argparse
import configparser
import json
import os
from pathlib import Path
import re
import sys

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software") if os.environ.get("GG_PREVIEW_SOFTWARE") else None

from PySide6.QtCore import Property, QEnum, QObject, QTimer, QUrl, Signal, Slot, ClassInfo  # noqa: E402
from PySide6.QtGui import QGuiApplication, QImage  # noqa: E402
from PySide6.QtQml import (QmlAttached, QmlElement, QmlUncreatable, QQmlApplicationEngine,  # noqa: E402
                           QQmlAbstractUrlInterceptor, qmlRegisterSingletonType, qmlRegisterType)
from PySide6.QtQuick import QQuickItem  # noqa: E402
from enum import IntEnum  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent

# ----------------------------------------------------------------- Wayland
QML_IMPORT_NAME = "Quickshell.Wayland"
QML_IMPORT_MAJOR_VERSION = 1


class LayershellAttached(QObject):
    changed = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._layer, self._ns, self._focus = 2, "quickshell", 0

    def _get_layer(self): return self._layer
    def _set_layer(self, v): self._layer = v; self.changed.emit()
    def _get_ns(self): return self._ns
    def _set_ns(self, v): self._ns = v; self.changed.emit()
    def _get_focus(self): return self._focus
    def _set_focus(self, v): self._focus = v; self.changed.emit()
    layer = Property(int, _get_layer, _set_layer, notify=changed)
    namespace = Property(str, _get_ns, _set_ns, notify=changed)
    keyboardFocus = Property(int, _get_focus, _set_focus, notify=changed)


@QmlElement
@QmlUncreatable("WlrLayershell is an attached property")
@QmlAttached(LayershellAttached)
class WlrLayershell(QObject):
    @staticmethod
    def qmlAttachedProperties(self, o):
        return LayershellAttached(o)


@QmlElement
@QmlUncreatable("enum")
class WlrLayer(QObject):
    @QEnum
    class Layer(IntEnum):
        Background = 0
        Bottom = 1
        Top = 2
        Overlay = 3


@QmlElement
@QmlUncreatable("enum")
class WlrKeyboardFocus(QObject):
    Focus = QEnum(IntEnum("Focus", {"None": 0, "Exclusive": 1, "OnDemand": 2}))   # "None" is a Python keyword


@QmlElement
@ClassInfo(DefaultProperty="surface")
class WlSessionLock(QObject):
    changed = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._locked, self._surface = False, None

    def _gl(self): return self._locked
    def _sl(self, v): self._locked = v; self.changed.emit()
    def _gs(self): return self._surface
    def _ss(self, v): self._surface = v; self.changed.emit()
    locked = Property(bool, _gl, _sl, notify=changed)
    secure = Property(bool, lambda self: False, notify=changed)
    surface = Property(QObject, _gs, _ss, notify=changed)


@QmlElement
class WlSessionLockSurface(QQuickItem):
    changed = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._color, self._screen = "black", None

    def _gc(self): return self._color
    def _sc(self, v): self._color = v; self.changed.emit()
    def _gsc(self): return self._screen
    def _ssc(self, v): self._screen = v; self.changed.emit()
    color = Property("QVariant", _gc, _sc, notify=changed)
    screen = Property("QVariant", _gsc, _ssc, notify=changed)


qmlRegisterSingletonType(QUrl.fromLocalFile(str(HERE / "qml/Wayland/ToplevelManager.qml")), "Quickshell.Wayland", 1, 0, "ToplevelManager")
qmlRegisterType(QUrl.fromLocalFile(str(HERE / "qml/Wayland/ScreencopyView.qml")), "Quickshell.Wayland", 1, 0, "ScreencopyView")


# Quickshell's ScriptModel: a list model over a JS array, each entry as modelData.
from PySide6.QtCore import QAbstractListModel, QModelIndex, Qt  # noqa: E402


class ScriptModel(QAbstractListModel):
    valuesChanged = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._values = []

    def roleNames(self):
        return {Qt.UserRole + 1: b"modelData"}

    def rowCount(self, parent=QModelIndex()):
        return 0 if parent.isValid() else len(self._values)

    def data(self, index, role=Qt.DisplayRole):
        if not index.isValid() or not 0 <= index.row() < len(self._values):
            return None
        return self._values[index.row()]

    def _get(self): return self._values

    def _set(self, v):
        self.beginResetModel()
        self._values = list(v.toVariant() if hasattr(v, "toVariant") else (v or []))
        self.endResetModel()
        self.valuesChanged.emit()
    values = Property("QVariantList", _get, _set, notify=valuesChanged)


qmlRegisterType(ScriptModel, "Quickshell", 1, 0, "ScriptModel")

# ----------------------------------------------------------------- fixtures
# (pattern over the command line, stdout, exit code). First match wins;
# "hang" never exits, like `gsettings monitor`.
FIXTURES: list[tuple[str, str, object]] = [
    (r"intelligence/helper\.py", json.dumps({"ok": True, "config": {"enabled": False,
        "textModel": "gemini-3.8-flash", "imageModel": "gemini-3.1-flash-image"},
        "hasKey": False, "environmentKey": False, "warning": ""}), 0),
    # The App Store's Flathub catalog (a sample, offline; its Mac catalog comes
    # from fixtures/casks.json through GG_MAC_CATALOG_URL).
    (r"software/helper\.py (catalog|refresh)", (HERE / "fixtures/flathub.json").read_text(), 0),
    (r"gsettings get org\.gnome\.desktop\.interface color-scheme", "{scheme}", 0),
    (r"gsettings get org\.gnome\.desktop\.interface accent-color", "'blue'", 0),
    (r"\bmonitor\b|--follow|\bsubscribe\b|inotifywait|tail -f|journalctl -f|sleep infinity", "", "hang"),
    (r"nmcli -t radio wifi|nmcli radio wifi$", "enabled\n", 0),
    (r"nmcli -t -f ACTIVE,SSID dev wifi", "Golden Gate\n", 0),
    (r"nmcli -t -f IN-USE,SIGNAL,SECURITY,SSID device wifi list",
     "*:86:WPA2:Golden Gate\n :64::Bay Area Guest\n :58:WPA2:Ferry Building\n :41:WPA3:Alcatraz-5G\n", 0),
    (r"nmcli -t -f TYPE,STATE d(ev(ice)?)?", "wifi:connected\nethernet:unavailable\n", 0),
    (r"golden-gate/airdrop\.json", '{"enabled": true, "mode": "everyone"}\n', 0),
    (r"bluetoothctl show", "Controller AA:BB:CC:DD:EE:FF golden-gate [default]\n\tPowered: yes\n", 0),
    (r"brightnessctl -m", "intel_backlight,backlight,768,80%,960\n", 0),
    (r"brightnessctl (g|get)$", "768\n", 0),
    (r"brightnessctl (m|max)$", "960\n", 0),
    (r"blueferry .*pairing-configuration-json", '{"configured": true}\n', 0),
]


# Stand-ins for system tools, put first on PATH for the commands that run for
# real: they answer as a typical laptop would.
FAKE_TOOLS = {
    "getent": 'case "$1" in passwd) echo "jordan:x:1000:1000:Jordan Avery:/home/jordan:/bin/bash";; group) echo "wheel:x:998:jordan";; esac',
    "hostname": "echo golden-gate",
    "hostnamectl": "echo golden-gate",
    "nmcli": 'case "$*" in *radio*) echo enabled;; *IN-USE*|*SIGNAL*) printf "*:86:WPA2:Golden Gate\\n :64::Bay Area Guest\\n :58:WPA2:Ferry Building\\n";; '
             '*TYPE,STATE*) printf "wifi:connected\\nethernet:unavailable\\n";; *ACTIVE,SSID*) printf "yes:Golden Gate\\nno:Bay Area Guest\\n";; *) ;; esac',
    "gsettings": 'case "$1 $3" in "get color-scheme") echo "$GG_PREVIEW_SCHEME";; "get accent-color") echo "\x27blue\x27";; esac',
    "bluetoothctl": 'case "$1" in show) printf "Controller AA:BB:CC:DD:EE:FF golden-gate [default]\\n\\tPowered: yes\\n";; devices) printf "Device AA:BB:CC:00:11:22 AirPods Pro\\n";; esac',
    "brightnessctl": 'case "$1" in -m) echo "intel_backlight,backlight,768,80%,960";; g|get) echo 768;; m|max) echo 960;; esac',
    "blueferry": "echo '{\"configured\": true, \"storage_state\": \"unlocked\"}'",
    "systemctl": "exit 3",
    "pactl": "exit 0",
    "flatpak": "exit 0",
}
# Never run for real: anything that would change the system or reach out.
DANGER = re.compile(r"\b(rm|mv|pkexec|sudo|systemctl|hyprctl|kill|pkill|reboot|poweroff|shutdown|dd|mkfs|chmod|chown|"
                    r"curl|wget|gio|xdg-open|notify-send|gg-pref|pacman|loginctl|qs|ssh|scp|git|npm|pip|"
                    r"open|write|save|delete|trash|move|rename|apply|install|remove|connect|disconnect|pair|power)\b")


# Read-only all the same, though a word above matches ("list trash:").
SAFE = re.compile(r"files/helper\.py list ")


class Preview(QObject):
    """The harness, as `__preview` in every QML context."""
    def __init__(self, env: dict, shell_dir: str, scheme: str):
        super().__init__()
        self._env = env
        self._shell_dir = shell_dir
        self._scheme = scheme
        self._ipc: list[QObject] = []
        self._servers: list[QObject] = []
        self._bin = HERE / "cache/bin"
        self._bin.mkdir(parents=True, exist_ok=True)
        for name, body in FAKE_TOOLS.items():
            f = self._bin / name
            f.write_text("#!/bin/sh\n" + body + "\n")
            f.chmod(0o755)
        self._icons = self._index_icons()
        self._entries = self._desktop_entries()
        self.verbose = False

    # -- properties
    env = Property("QVariantMap", lambda self: self._env, constant=True)
    shellDir = Property(str, lambda self: self._shell_dir, constant=True)
    desktopEntries = Property("QVariantList", lambda self: self._entries, constant=True)

    @Slot(str)
    def log(self, text):
        if self.verbose:
            print("·", text, file=sys.stderr)

    @Slot("QVariant", result="QVariantMap")
    def run(self, cmd):
        if hasattr(cmd, "toVariant"):
            cmd = cmd.toVariant()
        line = " ".join(str(c) for c in (cmd or []))
        for pattern, out, code in FIXTURES:
            if re.search(pattern, line):
                if code == "hang":
                    return {"stdout": "", "stderr": "", "code": 0, "hang": True}
                return {"stdout": out.replace("{scheme}", self._scheme), "stderr": "", "code": code}
        if cmd and (not DANGER.search(line) or SAFE.search(line)):
            # Read-only commands run for real, in the sample home, with the fake tools first.
            import subprocess
            env = {**os.environ, **{k: str(v) for k, v in self._env.items()},
                   "PATH": f"{self._bin}:/usr/local/bin:/usr/bin:/bin", "GG_PREVIEW_SCHEME": self._scheme}
            try:
                r = subprocess.run([str(c) for c in cmd], capture_output=True, text=True, timeout=6,
                                   env=env, cwd=self._env.get("HOME"), stdin=subprocess.DEVNULL)
                self.log(f"ran {line[:100]} → {r.returncode}")
                return {"stdout": r.stdout, "stderr": r.stderr, "code": r.returncode}
            except (OSError, subprocess.SubprocessError) as e:
                self.log(f"failed {line[:100]}: {e}")
        return {"stdout": "", "stderr": "", "code": 0}

    @Slot(str, result="QVariant")
    def readFile(self, path):
        try:
            return Path(path).read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            return None

    @Slot(str, result=str)
    def iconPath(self, name):
        if not name:
            return ""
        if name.startswith("/") and Path(name).exists():
            return QUrl.fromLocalFile(name).toString()
        p = self._icons.get(name)
        return QUrl.fromLocalFile(str(p)).toString() if p else ""

    @Slot(QObject)
    def registerIpc(self, obj):
        self._ipc.append(obj)

    @Slot(QObject)
    def registerNotificationServer(self, obj):
        self._servers.append(obj)

    # -- harness side
    def ipc(self, target: str, function: str, args: list) -> bool:
        from PySide6.QtCore import QMetaObject, Q_ARG
        for h in self._ipc:
            if h.property("target") == target:
                mo = h.metaObject()
                for i in range(mo.methodCount()):
                    m = mo.method(i)
                    if bytes(m.name()).decode() == function:
                        types = [bytes(t).decode() for t in m.parameterTypes()]
                        conv = []
                        for t, a in zip(types, args):
                            conv.append(int(a) if t == "int" else (a in ("1", "true") if t == "bool" else a))
                        if types and len(conv) != len(types):
                            print(f"preview: {target}.{function} takes {len(types)} arguments", file=sys.stderr)
                            return False
                        QMetaObject.invokeMethod(h, function, *[Q_ARG(t if t in ("int", "bool") else "QString", v)
                                                                for t, v in zip(types, conv)])
                        return True
        print(f"preview: no IPC handler {target}.{function}", file=sys.stderr)
        return False

    def notify(self, fields: dict):
        from PySide6.QtCore import QMetaObject, Q_ARG
        for s in self._servers:
            QMetaObject.invokeMethod(s, "__send", Q_ARG("QVariant", fields))

    # -- indexing
    def _index_icons(self) -> dict:
        found = {}
        for base in (ROOT / "icons/GoldenGate/scalable", ROOT / "icons/GoldenGate/512x512",
                     ROOT / "icons/GoldenGate/symbolic", Path("/usr/share/icons/hicolor")):
            if base.is_dir():
                for f in base.rglob("*"):
                    if f.suffix in (".svg", ".png"):
                        found.setdefault(f.stem, f)
        return found

    def _desktop_entries(self) -> list:
        out = []
        for f in sorted((ROOT / "apps/desktop").glob("*.desktop")):
            cp = configparser.ConfigParser(interpolation=None, strict=False)
            cp.optionxform = str
            try:
                cp.read_string(f.read_text(encoding="utf-8"))
            except configparser.Error:
                continue
            d = cp["Desktop Entry"] if cp.has_section("Desktop Entry") else {}
            out.append({
                "id": f.stem, "name": d.get("Name", f.stem), "genericName": d.get("GenericName", ""),
                "comment": d.get("Comment", ""), "icon": d.get("Icon", ""), "execString": d.get("Exec", ""),
                "categories": [c for c in d.get("Categories", "").split(";") if c],
                "keywords": [c for c in d.get("Keywords", "").split(";") if c],
                "noDisplay": d.get("NoDisplay", "false") == "true",
            })
        return out


class SingletonDirs(QQmlAbstractUrlInterceptor):
    """Quickshell honours `pragma Singleton` in a folder without a qmldir
    (shell/components/Prefs.qml); Qt needs the folder's qmldir to say so.
    Such folders get a generated one, next to nothing in the repository."""
    def __init__(self):
        super().__init__()
        self.cache = HERE / "cache/qmldirs"

    def intercept(self, url, kind):
        if kind != QQmlAbstractUrlInterceptor.DataType.QmldirFile or not url.isLocalFile():
            return url
        path = Path(url.toLocalFile())
        folder = path.parent
        if path.exists() or not folder.is_dir() or ROOT not in folder.parents:
            return url
        lines = []
        for f in sorted(folder.glob("*.qml")):
            head = f.read_text(encoding="utf-8", errors="ignore")[:400]
            single = re.search(r"^pragma Singleton", head, re.M)
            lines.append(f"{'singleton ' if single else ''}{f.stem} 1.0 {f.name}")
        if not any(l.startswith("singleton") for l in lines):
            return url
        # Next to the files (so their names resolve), but under the cache by symlink.
        out = self.cache / str(abs(hash(str(folder))))
        out.mkdir(parents=True, exist_ok=True)
        for f in folder.glob("*.qml"):
            link = out / f.name
            if not link.exists():
                link.symlink_to(f)
        (out / "qmldir").write_text("\n".join(lines) + "\n")
        return QUrl.fromLocalFile(str(out / "qmldir"))


NOTES = {
    "Personal/Weekend in Sonoma.md": "# Weekend in Sonoma\n\nLeave Friday after lunch to beat the bridge traffic.\n\n- Book the cottage in Glen Ellen\n- Picnic at Jack London park\n- Dinner reservation Saturday, 7:30\n",
    "Personal/Groceries.md": "# Groceries\n\n- [x] Sourdough\n- [x] Figs\n- [ ] Coffee beans\n- [ ] Burrata\n- [ ] Basil\n",
    "Work/Design review.md": "# Design review\n\nControl Center uses the Dock's glass; detail views sit on a module card.\n\n**Follow-ups**\n\n1. Slider metrics against macOS\n2. Launchpad label contrast\n",
    "Notes/Packing for Tahoe.md": "# Packing for Tahoe\n\n- Chains for the car\n- Thermos\n- The good gloves\n",
    "Work/Release checklist.md": "# Release checklist\n\n- [x] Build the ISO\n- [x] Boot test on the ThinkPad\n- [ ] Publish the update\n",
    "Notes/Ideas.md": "# Ideas\n\nA widget for the ferry schedule. A Focus filter that hides work notes after six.\n",
}
PHOTO = """<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="800" viewBox="0 0 1200 800">
<defs><linearGradient id="s" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{a}"/><stop offset="1" stop-color="{b}"/></linearGradient></defs>
<rect width="1200" height="800" fill="url(#s)"/><circle cx="{sx}" cy="{sy}" r="70" fill="{sun}" opacity=".9"/>
<path d="M0 560 Q300 {h1} 600 540 T1200 520 V800 H0z" fill="{c}" opacity=".85"/>
<path d="M0 640 Q400 {h2} 800 650 T1200 620 V800 H0z" fill="{d}"/></svg>"""
PHOTOS = [
    dict(a="#ff9a62", b="#ffd8a8", sun="#fff3c4", sx=820, sy=300, c="#c4573a", d="#5a2a32", h1=420, h2=560),
    dict(a="#4f8fe0", b="#bfe0ff", sun="#ffffff", sx=300, sy=220, c="#2e6b4f", d="#1d3b2c", h1=470, h2=600),
    dict(a="#1b2550", b="#7a5ea8", sun="#ffe9b0", sx=900, sy=200, c="#30285a", d="#120f26", h1=430, h2=580),
    dict(a="#8fd3f4", b="#e8f7ff", sun="#fffbe0", sx=600, sy=180, c="#d9b48a", d="#9c7651", h1=500, h2=620),
    dict(a="#f7c6d9", b="#fde8d0", sun="#ffffff", sx=200, sy=260, c="#7fb0a3", d="#3f6b62", h1=440, h2=590),
    dict(a="#0f3d5e", b="#3aa0c8", sun="#d8f6ff", sx=1000, sy=160, c="#0b5a6b", d="#06323d", h1=480, h2=610),
]


BRIEF = """# CitronOS: design brief

A desktop that feels like home on a Mac, on hardware you already own.

## Principles

- Familiar first. The menu bar, the Dock, Spotlight and the traffic lights are
  where your hands expect them, and ⌘ works the way it does on a Mac.
- Calm glass. Materials take their colour from what is behind them and get
  out of the way of the content.
- Nothing to configure. Wi-Fi, Bluetooth, printers and updates work from the
  first boot; the settings are there when you want them.

## This quarter

1. Window tiling from the green button and the Window menu
2. Quick Look in Files (press Space)
3. Spotlight answers: maths, units and System Settings

Review on Thursday at 10:30 in the studio.
"""


def populate_home(home: Path) -> None:
    """A lived-in home folder for the apps to show: notes, documents and photos."""
    stamp = home / ".preview-populated-5"
    if stamp.exists():
        return
    for rel, text in NOTES.items():
        f = home / "Documents/Notes" / rel
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_text(text)
    for rel, size in (("Documents/Q4 Plan.pdf", 48_000), ("Documents/Budget 2026.xlsx", 22_000),
                      ("Downloads/inter-4.1.zip", 2_400_000),
                      ("Downloads/ferry-schedule.pdf", 120_000), ("Desktop/Moodboard.key", 860_000),
                      ("Music/.keep", 0), ("Videos/.keep", 0)):
        f = home / rel
        f.parent.mkdir(parents=True, exist_ok=True)
        f.write_bytes(b"\0" * size)
    (home / "Documents/CitronOS brief.md").write_text(BRIEF)
    # Two things in the Trash, with where they came from.
    for name, origin in (("Old draft.md", "Documents/Old draft.md"), ("IMG_0412.png", "Desktop/IMG_0412.png")):
        (home / ".local/share/Trash/files").mkdir(parents=True, exist_ok=True)
        (home / ".local/share/Trash/info").mkdir(parents=True, exist_ok=True)
        (home / ".local/share/Trash/files" / name).write_text("draft")
        (home / ".local/share/Trash/info" / f"{name}.trashinfo").write_text(
            f"[Trash Info]\nPath={home / origin}\nDeletionDate=2026-10-02T18:20:00\n")
    pics = home / "Pictures"
    pics.mkdir(parents=True, exist_ok=True)
    names = ["Sunset over Tiburon", "Muir Woods", "Night at Ocean Beach", "Baker Beach", "Dolores Park", "Lands End"]
    for name, look in zip(names, PHOTOS):
        svg = pics / f".{name}.svg"
        svg.write_text(PHOTO.format(**look))
        os.system(f"rsvg-convert '{svg}' -o '{pics / (name + '.png')}'")
        svg.unlink()
    os.system(f"rsvg-convert -w 1600 '{ROOT}/prototype/assets/wallpapers/dusk.svg' -o '{home / 'Desktop/Screenshot 2026-10-03 at 9.12.png'}'")
    stamp.write_text("")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("kind", choices=["shell", "app"])
    ap.add_argument("qml", nargs="?", help="the app's QML file (for `app`)")
    ap.add_argument("-o", "--out", required=True)
    ap.add_argument("--dark", action="store_true")
    ap.add_argument("--do", action="append", default=[], help="target.function[:arg…], as qs ipc call")
    ap.add_argument("--notify", action="store_true", help="send two sample notifications")
    ap.add_argument("--env", action="append", default=[], help="NAME=value for Quickshell.env")
    ap.add_argument("--size", default="1440x900")
    ap.add_argument("--wait", type=int, default=900, help="ms to settle before each step")
    ap.add_argument("--crop", default="", help="x,y,w,h of the screenshot to keep")
    ap.add_argument("--require-object", default="",
                    help="fail when a required loaded QML objectName is absent (catches empty Loader panes)")
    ap.add_argument("-v", "--verbose", action="store_true")
    a = ap.parse_args()

    w, h = (int(v) for v in a.size.split("x"))
    wallpaper = HERE / "cache/tide.png"
    if not wallpaper.exists():
        wallpaper.parent.mkdir(parents=True, exist_ok=True)
        os.system(f"rsvg-convert -w 2880 -h 1800 '{ROOT}/prototype/assets/wallpapers/tide.svg' -o '{wallpaper}'")
    home = HERE / "cache/home"
    (home / ".config/golden-gate").mkdir(parents=True, exist_ok=True)
    populate_home(home)
    env = {"HOME": str(home), "XDG_CONFIG_HOME": str(home / ".config"), "USER": "jordan",
           "GG_WALLPAPER": str(wallpaper), "XDG_CURRENT_DESKTOP": "Hyprland",
           "GG_MAC_CATALOG_URL": (HERE / "fixtures/casks.json").as_uri()}
    for kv in a.env:
        k, _, v = kv.partition("=")
        env[k] = v
    os.environ["QML_XHR_ALLOW_FILE_READ"] = "1"
    # CitronOS's font rules (SF Pro → Inter, SF Mono → JetBrains Mono), as installed.
    fonts_conf = HERE / "cache/fonts.conf"
    fonts_conf.write_text('<?xml version="1.0"?>\n<!DOCTYPE fontconfig SYSTEM "fonts.dtd">\n<fontconfig>\n'
                          '  <include ignore_missing="yes">/etc/fonts/fonts.conf</include>\n'
                          f'  <include ignore_missing="yes">{ROOT}/themes/fontconfig/60-golden-gate.conf</include>\n'
                          '</fontconfig>\n')
    os.environ["FONTCONFIG_FILE"] = str(fonts_conf)

    if a.kind == "shell":
        target = ROOT / "shell/shell.qml"
    else:
        if not a.qml:
            ap.error("app needs a QML file")
        target = (ROOT / a.qml).resolve() if not Path(a.qml).is_absolute() else Path(a.qml)

    app = QGuiApplication(sys.argv[:1])
    preview = Preview(env, str(target.parent), "'prefer-dark'" if a.dark else "'default'")
    preview.verbose = a.verbose
    engine = QQmlApplicationEngine()
    interceptor = SingletonDirs()
    engine.addUrlInterceptor(interceptor)
    engine.addImportPath(str(HERE / "qml"))
    engine.rootContext().setContextProperty("__preview", preview)
    engine.setInitialProperties({"targetUrl": QUrl.fromLocalFile(str(target)), "screenWidth": w,
                                 "screenHeight": h, "dark": a.dark})
    engine.load(QUrl.fromLocalFile(str(HERE / "Desktop.qml")))
    if not engine.rootObjects():
        return 2
    window = engine.rootObjects()[0]

    steps = list(a.do)
    if a.notify:
        steps.insert(0, "@notify")

    def finish():
        if a.require_object:
            obj = window.findChild(QObject, a.require_object)
            height = obj.property("height") if obj else None
            visible = obj.property("visible") if obj else False
            if obj is None or visible is False or height is None or float(height) < 100:
                print("preview: required component did not render with visible content: "
                      + a.require_object, file=sys.stderr)
                app.exit(3)
                return
        img: QImage = window.grabWindow()
        if a.crop:
            x, y, cw, ch = (int(v) for v in a.crop.split(","))
            img = img.copy(x, y, cw, ch)
        img.save(a.out)
        print(a.out)
        app.quit()

    def step():
        if not steps:
            finish()                # the last step (or the start) has already had its wait
            return
        s = steps.pop(0)
        if s == "@notify":
            preview.notify({"id": 1, "appName": "Messages", "appIcon": "org.goldengate.Messages",
                            "desktopEntry": "org.goldengate.Messages", "summary": "Sam",
                            "body": "Ferry at 6? I'll grab a table outside."})
            preview.notify({"id": 2, "appName": "Calendar", "appIcon": "org.goldengate.Calendar",
                            "desktopEntry": "org.goldengate.Calendar", "summary": "Design review",
                            "body": "Today at 10:30 · Studio"})
        else:
            fn, *args = s.split(":")
            target_name, _, function = fn.partition(".")
            preview.ipc(target_name, function, args)
        QTimer.singleShot(a.wait, step)

    QTimer.singleShot(a.wait, step)
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
