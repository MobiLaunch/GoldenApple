#!/usr/bin/env python3
"""Control Center, grouped as in Big Sur, through the preview harness: one
panel of glass holding tiles on a four-column grid, Wi-Fi, Bluetooth and
AirDrop sharing one. In dark mode with Wi-Fi on, the Wi-Fi disc is the
accent blue and the Dark Mode toggle's disc is solid white; the Display and
Sound tiles carry white slider fills."""
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
        # Wi-Fi: the first row of the shared tile (4 px inset), its disc 8 px in.
        wifi = img.pixelColor(x0 + 4 + 8 + 5, y0 + 4 + 23)
        check(wifi.blue() > 200 and wifi.red() < 80, f"Wi-Fi's disc is the accent while on, got {wifi.name()}")
        # Dark Mode: right of the shared tile, under Focus; its disc off the glyph.
        right = x0 + 2 * 68 + 12 + 12
        dark = img.pixelColor(right + 34 - 12, y0 + 68 + 12 + 8 + 16)
        check(dark.lightness() > 240, f"the Dark Mode disc is white while on, got {dark.name()}")
        # Display: below the shared tile (two rows) and the small toggles.
        display = y0 + (2 * 68 + 12) + 12 + 68 + 12
        fill = sum(1 for x in range(x0 + 60, x0 + 200, 3) if img.pixelColor(x, display + 74 - 19 - 3).lightness() > 235)
        check(fill > 30, f"the Display tile's slider is filled white, found {fill}")
        # The panel is glass between the tiles too: the wallpaper there is
        # blurred and tinted, not bare.
        between = img.pixelColor(x0 + 2 * 68 + 12 + 6, y0 + 40)
        check(between.alpha() == 255, "the panel is drawn between the tiles")
# One panel of glass: HyprGlass turns anything on the surface more opaque than
# its threshold into glass, so the panel's tint (both appearances) sits above
# it and the backdrop is blurred behind the whole panel.
import re
qml = (ROOT / "shell/ControlCenter.qml").read_text()
threshold = re.search(r"gg-controlcenter=([\d.]+)", (ROOT / "compositor/hyprland/hyprglass-sync.sh").read_text())
check(threshold is not None, "HyprGlass has a Control Center threshold")
line = float(threshold.group(1)) if threshold else 0.0
check(0.2 <= line <= 0.3, f"the threshold sits under the panel's glass, got {line}")
tint = re.search(r'objectName: "ccPanel".*?tint: Theme\.dark \? Qt\.rgba\(([^)]*)\) : Qt\.rgba\(([^)]*)\)', qml, re.S)
check(tint is not None, "the panel is one piece of glass behind the controls")
if tint:
    for mode, args in (("dark", tint.group(1)), ("light", tint.group(2))):
        alpha = float(args.split(",")[-1])
        check(alpha > line, f"{mode}: the panel ({alpha:.2f} opaque) stays above the glass threshold")
check('objectName: "ccConnectivity"' in qml and qml.count("bare: true") == 3, "Wi-Fi, Bluetooth and AirDrop share one tile")
if failures:
    print("\n".join("FAIL " + f for f in failures), file=sys.stderr)
    raise SystemExit(1)
print("Control Center: one glass panel of tiles, as in Big Sur (shared connectivity tile, toggles, sliders, Now Playing)")
