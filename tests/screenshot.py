#!/usr/bin/env python3
"""The screenshot toolbar (⇧⌘5), through the preview harness: the selection
with its handles and the toolbar draw, and the keys, Control Center's Capture,
the menu bar's stop button and the packages are wired. (The commands grim and
wf-recorder get are tested in tests/logic.mjs.)"""
from __future__ import annotations

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


with tempfile.TemporaryDirectory() as tmp:
    out = Path(tmp) / "toolbar.png"
    proc = subprocess.run([sys.executable, str(ROOT / "tools/preview/preview.py"), "shell", "--do", "screenshot.toolbar",
                           "-v", "-o", str(out)], capture_output=True, text=True, timeout=180, cwd=ROOT)
    errors = [l for l in proc.stderr.splitlines() if re.search(r"Screenshot\.qml.*(Error|is not a type|unavailable|TypeError)", l)
              or "Type Screenshot unavailable" in l]
    check(proc.returncode == 0 and out.exists(), f"preview failed: {proc.stderr[-300:]}")
    check(not errors, f"QML errors: {errors[:3]}")
    img = QImage(str(out))
    if not img.isNull():
        w, h = img.width(), img.height()
        # The default selection: the middle half, with white handles at its corners.
        corner = img.pixelColor(w // 4, h // 4)
        check(corner.lightness() > 230, f"a handle at the selection's corner, got {corner.name()}")
        # Outside the selection is dimmed; inside isn't.
        outside = img.pixelColor(w // 2, h // 8)
        check(outside.lightness() < 170, f"outside the selection is dimmed, got {outside.name()}")
        # The toolbar: a light glass bar near the bottom, across the middle.
        bar = sum(1 for x in range(w // 2 - 200, w // 2 + 200, 4) if img.pixelColor(x, h - 148).lightness() > 195)
        check(bar > 60, f"the toolbar near the bottom, found {bar} light pixels")

conf = (ROOT / "compositor/hyprland/hyprland.conf").read_text()
for key, call in [("$mod SHIFT, 3", "screen"), ("$mod SHIFT, 4", "area"), ("$mod SHIFT, 5", "toolbar"),
                  ("$mod CTRL SHIFT, 3", "screenToClipboard"), ("$mod CTRL SHIFT, 4", "areaToClipboard")]:
    check(f"bind = {key}, exec, $qs screenshot {call}" in conf, f"{key} → screenshot {call}")
check("slurp" not in conf, "the old slurp bindings are gone")
check('cc.ipc("screenshot toolbar")' in (ROOT / "shell/ControlCenter.qml").read_text(), "Control Center's Screenshot control opens the toolbar")
menubar = (ROOT / "shell/MenuBar.qml").read_text()
check("bar.screenshots?.recording" in menubar and "stopRecording()" in menubar, "the menu bar stops a recording")
packages = (ROOT / "distro/archiso/packages.x86_64").read_text().split()
for pkg in ("grim", "wf-recorder", "wl-clipboard", "sound-theme-freedesktop"):
    check(pkg in packages, f"{pkg} is on the image")

if failures:
    print("\n".join("FAIL " + f for f in failures), file=sys.stderr)
    raise SystemExit(1)
print("Screenshots: the ⇧⌘5 toolbar and selection draw; keys, Capture, stop button and packages wired")
