#!/usr/bin/env python3
"""Desktop widgets, through the preview harness: a new account's desktop shows
the Calendar (today ringed in red), Clock and Weather widgets on the left;
Edit Widgets shows each widget's remove button and the gallery above the Dock
with its Done button; adding a widget from the gallery puts it in the next
free cell down the left. Also checks the wiring that makes them work on a real
system: always loaded, an Edit Widgets… item on the desktop's menu, input
only over the widgets, and HyprGlass glass behind them."""
from __future__ import annotations

from pathlib import Path
import re
import subprocess
import sys
import tempfile

from PySide6.QtGui import QImage

ROOT = Path(__file__).resolve().parents[1]
failures: list[str] = []
CELL, GAP, MARGIN, TOP = 164, 16, 24, 46


def check(cond: bool, what: str) -> None:
    if not cond:
        failures.append(what)


def render(tmp: Path, name: str, *args: str) -> QImage:
    out = tmp / f"{name}.png"
    config = tmp / f"config-{name}"
    config.mkdir()
    proc = subprocess.run([sys.executable, str(ROOT / "tools/preview/preview.py"), "shell", "-v",
                           "--env", f"XDG_CONFIG_HOME={config}", "--env", f"GG_WEATHER_FIXTURE={tmp / 'wx'}",
                           *args, "-o", str(out)], capture_output=True, text=True, timeout=180, cwd=ROOT)
    bad = [l for l in proc.stderr.splitlines()
           if re.search(r"DesktopWidgets\.qml|widgets/", l) and re.search(r"Error|is not|Unable|undefined", l)]
    check(proc.returncode == 0 and out.exists(), f"{name}: preview failed: {proc.stderr[-300:]}")
    check(not bad, f"{name}: QML errors: {bad[:3]}")
    return QImage(str(out))


def cell(col: int, row: int) -> tuple[int, int]:
    return MARGIN + col * (CELL + GAP), TOP + row * (CELL + GAP)


with tempfile.TemporaryDirectory() as t:
    tmp = Path(t)
    subprocess.run([sys.executable, str(ROOT / "apps/weather/tests/make-fixture.py"), str(tmp / "wx")],
                   check=True, capture_output=True)

    img = render(tmp, "desktop")
    if not img.isNull():
        x, y = cell(0, 0)
        red = sum(1 for i in range(x, x + CELL, 2) for j in range(y, y + CELL, 2)
                  if (c := img.pixelColor(i, j)).red() > 220 and c.green() < 90 and c.blue() < 90)
        check(red > 20, f"the Calendar widget rings today in red (found {red} red pixels)")
        x, y = cell(1, 0)
        dial = img.pixelColor(x + CELL // 2 + 30, y + CELL // 2 + 30)
        check(dial.lightness() > 235, f"the Clock widget's dial is white in light mode, got {dial.name()}")
        hand = sum(1 for i in range(x + 20, x + CELL - 20) for j in range(y + 20, y + CELL - 20)
                   if (c := img.pixelColor(i, j)).red() > 230 and 120 < c.green() < 180 and c.blue() < 60)
        check(hand > 15, f"the Clock widget has its orange second hand (found {hand})")
        x, y = cell(0, 1)
        # Most of the medium widget is sky, not one pixel that fonts can move text onto.
        cells = [(i, j) for i in range(x + 8, x + 2 * CELL + GAP - 8, 4) for j in range(y + 8, y + CELL - 8, 4)]
        skyish = sum(1 for i, j in cells if (c := img.pixelColor(i, j)).lightness() < 190 and c.blue() > c.red())
        check(skyish > len(cells) * 0.5, f"the Weather widget paints the sky ({skyish} of {len(cells)} samples)")
        white = sum(1 for i in range(x + 15, x + 120) for j in range(y + 30, y + 75) if img.pixelColor(i, j).lightness() > 245)
        check(white > 150, f"the Weather widget shows the temperature (found {white} white pixels)")

    img = render(tmp, "edit", "--do", "widgets.edit")
    if not img.isNull():
        x, y = cell(0, 0)
        badge = img.pixelColor(x - 8 + 11, y - 8 + 5)
        check(180 < badge.lightness() < 245, f"each widget has its remove button while editing, got {badge.name()}")
        top = img.height() - 104 - 404
        done = sum(1 for i in range(img.width() // 2, img.width()) for j in range(top + 18, top + 46)
                   if (c := img.pixelColor(i, j)).blue() > 200 and c.red() < 60)
        check(done > 200, f"the gallery shows its Done button above the Dock (found {done})")

    img = render(tmp, "add", "--do", "widgets.add:music:medium")
    if not img.isNull():
        x, y = cell(0, 2)
        cover = img.pixelColor(x + 15 + 40, y + 15 + 30)
        check(cover.red() > 220 and cover.green() < 110, f"the added Music widget goes in the next free cell, got {cover.name()}")

shell = (ROOT / "shell/shell.qml").read_text()
check("DesktopWidgets { id: desktopWidgets }" in shell and "GG_WIDGETS" not in shell, "widgets are always on, not behind GG_WIDGETS")
check("Edit Widgets…" in (ROOT / "shell/Wallpaper.qml").read_text(), "the desktop's menu has Edit Widgets…")
board = (ROOT / "shell/DesktopWidgets.qml").read_text()
check("WlrLayer.Bottom" in board, "widgets sit above the wallpaper and under windows")
check(re.search(r"mask: Region \{ item: root\.editing \? everything : null; regions: root\.editing \? \[\] : tiles\.regions \}", board) is not None,
      "input only over the widgets (the desktop's menu still opens around them)")
glass = (ROOT / "compositor/hyprland/hyprglass-sync.sh").read_text()
check("gg-widgets" in re.search(r"layers:namespaces \"([^\"]+)\"", glass).group(1), "HyprGlass makes glass behind the widgets")

if failures:
    for f in failures:
        print("FAIL", f)
    sys.exit(1)
print("Desktop widgets: Calendar, Clock and Weather on the desktop; editing, the gallery and adding work")
