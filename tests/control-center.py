#!/usr/bin/env python3
"""Control Center, as in macOS 26, through the preview harness: separate glass
controls on a four-column grid. In dark mode with Wi-Fi on, the Wi-Fi
capsule's disc is the accent blue and the Dark Mode circle is solid white;
the Display and Sound tiles carry white slider fills."""
from __future__ import annotations

from pathlib import Path
import subprocess
import sys
import tempfile

from PySide6.QtGui import QImage

ROOT = Path(__file__).resolve().parents[1]
failures: list[str] = []


def check(cond: bool, what: str) -> None:
    if not cond:
        failures.append(what)


with tempfile.TemporaryDirectory() as tmp:
    out = Path(tmp) / "cc.png"
    proc = subprocess.run([sys.executable, str(ROOT / "tools/preview/preview.py"), "shell", "--dark",
                           "--do", "controlcenter.toggle", "-v", "-o", str(out)],
                          capture_output=True, text=True, timeout=180, cwd=ROOT)
    bad = [l for l in proc.stderr.splitlines() if "ControlCenter.qml" in l and ("Error" in l or "is not" in l or "Unable" in l)]
    check(proc.returncode == 0 and out.exists(), f"preview failed: {proc.stderr[-300:]}")
    check(not bad, f"QML errors: {bad[:3]}")
    img = QImage(str(out))
    if not img.isNull():
        # The panel's grid starts 14 px inside the panel at the screen's top right.
        x0 = img.width() - 10 - 4 - (4 * 68 + 3 * 12 + 28) + 14
        y0 = 8 + 24 + 14
        wifi = img.pixelColor(x0 + 13 + 21 - 8, y0 + 34)            # the disc, beside its glyph
        check(wifi.blue() > 200 and wifi.red() < 80, f"Wi-Fi's disc is the accent while on, got {wifi.name()}")
        row3 = y0 + 2 * (68 + 12) + 68 + 12
        dark = img.pixelColor(x0 + 12, row3 + 34)                    # the Dark Mode circle, off its glyph
        check(dark.lightness() > 240, f"the Dark Mode circle is white while on, got {dark.name()}")
        display = y0 + 3 * (68 + 12) + 68 + 12
        fill = sum(1 for x in range(x0 + 60, x0 + 200, 3) if img.pixelColor(x, display + 74 - 19 - 3).lightness() > 235)
        check(fill > 30, f"the Display tile's slider is filled white, found {fill}")

if failures:
    print("\n".join("FAIL " + f for f in failures), file=sys.stderr)
    raise SystemExit(1)
print("Control Center: the macOS 26 grid draws (capsules, circles, sliders)")
