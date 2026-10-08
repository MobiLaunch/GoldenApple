#!/usr/bin/env python3
"""The lock screen, through the preview harness (GG_LOCK_PREVIEW): asleep it
shows the date, the large clock, the battery and the user, with no password
field; typing wakes it and the field rises with the dots in it. Also checks
the wiring around it: the right password plays the unlock animation before the
session is released, and the session lock keeps keyboard focus on the text."""
from __future__ import annotations

from pathlib import Path
import re
import subprocess
import sys
import tempfile

from PySide6.QtGui import QImage

ROOT = Path(__file__).resolve().parents[1]
failures: list[str] = []
W, H = 1440, 900


def check(cond: bool, what: str) -> None:
    if not cond:
        failures.append(what)


def render(tmp: Path, name: str, *args: str) -> QImage:
    out = tmp / f"{name}.png"
    proc = subprocess.run([sys.executable, str(ROOT / "tools/preview/preview.py"), "shell", "-v",
                           "--env", "GG_LOCK_PREVIEW=1", *args, "-o", str(out)],
                          capture_output=True, text=True, timeout=180, cwd=ROOT)
    bad = [l for l in proc.stderr.splitlines()
           if re.search(r"Lock(Surface|Preview)\.qml", l) and re.search(r"Error|is not|Unable|undefined|loop", l)]
    check(proc.returncode == 0 and out.exists(), f"{name}: preview failed: {proc.stderr[-300:]}")
    check(not bad, f"{name}: QML errors: {bad[:3]}")
    return QImage(str(out))


def white(img: QImage, x0: int, y0: int, x1: int, y1: int, step: int = 2) -> int:
    return sum(1 for x in range(x0, x1, step) for y in range(y0, y1, step) if img.pixelColor(x, y).lightness() > 242)


with tempfile.TemporaryDirectory() as t:
    tmp = Path(t)
    asleep = render(tmp, "asleep")
    awake = render(tmp, "awake", "--do", "lockpreview.type:hunter22")
    if not asleep.isNull() and not awake.isNull():
        check(white(asleep, 450, 90, 990, 280) > 1500, "asleep: the large clock is drawn")
        check(white(asleep, W - 80, 14, W - 10, 36, 1) > 20, "asleep: the battery shows top right")
        # The field sits under the name, in the bottom fifth of the screen.
        rows = range(int(H * 0.8), int(H * 0.95))
        dots, row = max((white(awake, W // 2 - 110, y, W // 2 + 60, y + 1, 1), y) for y in rows)
        check(dots > 25, f"awake: the password's dots show in the field (found {dots} in a row)")
        none = white(asleep, W // 2 - 110, row, W // 2 + 60, row + 1, 1)
        check(none < 12, f"asleep: no password field until it wakes (found {none} on the field's row)")
        # Waking dims the wallpaper behind the clock.
        a, b = asleep.pixelColor(200, 500), awake.pixelColor(200, 500)
        check(b.lightness() < a.lightness() - 8, f"awake: the wallpaper dims ({a.name()} → {b.name()})")

lock = (ROOT / "shell/LockScreen.qml").read_text()
check(re.search(r"PamResult\.Success\)[^\n]*root\.surfaces\.forEach\(\(s\) => s\.unlock\(\)\)", lock) is not None,
      "the right password plays the unlock animation")
check("onUnlocked: session.locked = false" in lock, "the session is released when the animation ends")
surface = (ROOT / "shell/components/LockSurface.qml").read_text()
check("field.forceActiveFocus()" not in surface, "focus goes to the password's text, not the field around it")
greeter = (ROOT / "themes/sddm/golden-gate/Main.qml").read_text()
check("login: true" in greeter and "onLoginSucceeded() { surface.unlock() }" in greeter, "the login window starts awake and animates out")

if failures:
    for f in failures:
        print("FAIL", f)
    sys.exit(1)
print("Lock screen: clock, battery and user asleep; the field and its dots awake; unlock animates")
