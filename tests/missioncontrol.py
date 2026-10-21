#!/usr/bin/env python3
"""Mission Control, through the preview harness (tools/preview).

With sample windows on three desktops (GG_PREVIEW_WINDOWS=1), Mission Control
draws the desktops along the top and this desktop's four windows spread out
below; App Exposé shows only the front app's window. The keys and trackpad
gestures that open it are wired in hyprland.conf. (The spread itself is tested
in tests/logic.mjs.)"""
from __future__ import annotations

from pathlib import Path
import re
import subprocess
import sys
import tempfile

from PySide6.QtGui import QImage

ROOT = Path(__file__).resolve().parents[1]
PREVIEW = ROOT / "tools/preview/preview.py"
failures: list[str] = []


def check(cond: bool, what: str) -> None:
    if not cond:
        failures.append(what)


def shot(tmp: Path, name: str, call: str, *env: str) -> QImage:
    out = tmp / f"{name}.png"
    args = [sys.executable, str(PREVIEW), "shell", "--wait", "1200", "--do", call, "-v", "-o", str(out)]
    for e in env:
        args += ["--env", e]
    proc = subprocess.run(args, capture_output=True, text=True, timeout=180, cwd=ROOT)
    errors = [l for l in proc.stderr.splitlines() if re.search(r"MissionControl\.qml.*(Error|TypeError|ReferenceError|Unable|is not)", l)]
    check(proc.returncode == 0 and out.exists(), f"{name}: preview failed: {proc.stderr[-400:]}")
    check(not errors, f"{name}: QML errors: {errors[:3]}")
    return QImage(str(out))


def windows_across(img: QImage, empty: QImage, y0: int, y1: int) -> int:
    """How many windows sit side by side between rows y0 and y1: runs of columns
    where the picture differs from the same view with no windows (gaps under
    20 px are bridged; runs under 60 px, such as text, don't count)."""
    cols = []
    for x in range(0, img.width(), 2):
        differs = sum(1 for y in range(y0, y1, 6)
                      if abs(img.pixelColor(x, y).lightness() - empty.pixelColor(x, y).lightness()) > 30)
        cols.append(differs > (y1 - y0) / 6 * 0.25)
    runs, start, gap = [], None, 0
    for i, on in enumerate(cols + [False] * 11):
        if on:
            if start is None:
                start = i
            gap = 0
        elif start is not None:
            gap += 1
            if gap > 10:
                runs.append((i - gap - start + 1) * 2)
                start, gap = None, 0
    return sum(1 for w in runs if w >= 60)


with tempfile.TemporaryDirectory() as tmp:
    tmp = Path(tmp)
    empty = shot(tmp, "empty", "missioncontrol.toggle", "GG_PREVIEW_WINDOWS=empty")
    img = shot(tmp, "mc", "missioncontrol.toggle", "GG_PREVIEW_WINDOWS=1")
    if not img.isNull() and not empty.isNull():
        top, bottom = windows_across(img, empty, 190, 420), windows_across(img, empty, 520, 780)
        check((top, bottom) == (2, 2), f"Mission Control: expected this desktop's four windows two by two, found {top} and {bottom}")
    img = shot(tmp, "expose", "missioncontrol.appExpose", "GG_PREVIEW_WINDOWS=1", "GG_PREVIEW_ACTIVE=org.goldengate.Notes")
    empty = shot(tmp, "expose-empty", "missioncontrol.appExpose", "GG_PREVIEW_WINDOWS=empty", "GG_PREVIEW_ACTIVE=org.goldengate.Notes")
    if not img.isNull() and not empty.isNull():
        across = windows_across(img, empty, 200, 700)
        check(across == 1, f"App Exposé: expected only Notes' window, found {across} side by side")
        bar = windows_across(img, empty, 20, 130)
        check(bar == 0, "App Exposé: no desktops bar")

conf = (ROOT / "compositor/hyprland/hyprland.conf").read_text()
for line, what in [("bind = CTRL, up, exec, $qs missioncontrol toggle", "⌃↑ opens Mission Control"),
                   ("bind = CTRL, down, exec, $qs missioncontrol appExpose", "⌃↓ opens App Exposé"),
                   ("bind = , XF86LaunchA, exec, $qs missioncontrol toggle", "the Mission Control key"),
                   ("gesture = 3, horizontal, workspace", "three fingers across switch desktops"),
                   ("gesture = 3, up, dispatcher, exec, qs -c golden-gate ipc call missioncontrol toggle", "three fingers up"),
                   ("gesture = 3, down, dispatcher, exec, qs -c golden-gate ipc call missioncontrol appExpose", "three fingers down")]:
    check(line in conf, what)
check(re.search(r"^# gesture", conf, re.M) is None, "no gesture left commented out")

if failures:
    print("\n".join("FAIL " + f for f in failures), file=sys.stderr)
    raise SystemExit(1)
print("Mission Control: desktops bar, spread windows and App Exposé draw; keys and gestures wired")
