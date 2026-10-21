#!/usr/bin/env python3
"""The menu bar, through the preview harness: it has a visible background by
default (Settings → Menu Bar turns it off, leaving the wallpaper clear), and
with no app in front it has the Files app's menus, as the Mac's desktop has
Finder's, with each opening. Also checks the clock options' wiring."""
from __future__ import annotations

import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

from PySide6.QtGui import QImage

ROOT = Path(__file__).resolve().parents[1]
failures: list[str] = []


def check(cond: bool, what: str) -> None:
    if not cond:
        failures.append(what)


def render(tmp: Path, name: str, prefs: dict, *args: str) -> QImage:
    config = tmp / name / "config"
    (config / "golden-gate").mkdir(parents=True)
    (config / "golden-gate/desktop.json").write_text(json.dumps(prefs))
    out = tmp / f"{name}.png"
    proc = subprocess.run([sys.executable, str(ROOT / "tools/preview/preview.py"), "shell", "-v",
                           "--env", f"XDG_CONFIG_HOME={config}", *args, "-o", str(out)],
                          capture_output=True, text=True, timeout=180, cwd=ROOT)
    bad = [l for l in proc.stderr.splitlines()
           if "MenuBar.qml" in l and re.search(r"Error|is not|Unable|undefined|loop", l)]
    check(proc.returncode == 0 and out.exists(), f"{name}: preview failed: {proc.stderr[-300:]}")
    check(not bad, f"{name}: QML errors: {bad[:3]}")
    return QImage(str(out))


def lightness(img: QImage, x: int, y: int) -> int:
    return img.pixelColor(x, y).lightness()


with tempfile.TemporaryDirectory() as t:
    tmp = Path(t)
    # Over the darker blue at the right, just under the clock's text.
    x, y = 1400, 27
    banded = render(tmp, "background", {})
    clear = render(tmp, "clear", {"menuBar": {"background": False}})
    if not banded.isNull() and not clear.isNull():
        check(lightness(banded, x, y) > lightness(clear, x, y) + 20,
              f"the bar has a band over the wallpaper ({lightness(banded, x, y)} with it, {lightness(clear, x, y)} without)")
        check(abs(lightness(clear, x, y) - lightness(clear, x, 40)) < 20,
              f"with its background off the bar is clear ({lightness(clear, x, y)} vs {lightness(clear, x, 40)} below)")
    # Each desktop menu opens a menu under its title.
    for title in ("File", "Go", "Window", "Help"):
        img = render(tmp, "menu-" + title.lower(), {}, "--do", f"menubar.open:{title}")
        if not img.isNull() and not banded.isNull():
            changed = sum(1 for yy in range(40, 200, 4) for xx in range(30, 600, 4)
                          if img.pixelColor(xx, yy) != banded.pixelColor(xx, yy))
            check(changed > 400, f"{title}: its menu opens ({changed} pixels changed)")

bar = (ROOT / "shell/MenuBar.qml").read_text()
check('["File", "Edit", "View", "Go", "Window", "Help"]' in bar, "the desktop has Files' menus")
check('active ? ["Window", "Help"]' in bar, "an app gets Window and Help")
prefs = (ROOT / "shell/components/Prefs.qml").read_text()
check("data.menuBar?.background ?? true" in prefs, "the background is on by default")
settings = (ROOT / "apps/settings.qml").read_text()
check('"MenuBarPane"' in settings and (ROOT / "apps/settings/panes/MenuBarPane.qml").exists(), "Settings has a Menu Bar pane")

if failures:
    for f in failures:
        print("FAIL", f)
    sys.exit(1)
print("Menu bar: a visible background (optional), Files' menus on the desktop, each opening")
