#!/usr/bin/env python3
"""The App Store, through the preview harness with its sample catalogs
(tools/preview/fixtures): Discover draws its editorial card and shelves, the
Mac Apps page says whether Darling is set up, and an app's page draws. Mac
app installs themselves are tested in tests/mac-apps.py."""
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


def shot(tmp: Path, name: str, *env: str) -> QImage:
    out = tmp / f"{name}.png"
    args = [sys.executable, str(ROOT / "tools/preview/preview.py"), "app", "apps/software.qml", "--wait", "1500", "-v", "-o", str(out)]
    for e in env:
        args += ["--env", e]
    proc = subprocess.run(args, capture_output=True, text=True, timeout=180, cwd=ROOT)
    errors = [l for l in proc.stderr.splitlines() if re.search(r"software\.qml.*(Error|TypeError|ReferenceError|Unexpected|expected|is not)", l)]
    check(proc.returncode == 0 and out.exists(), f"{name}: preview failed: {proc.stderr[-300:]}")
    check(not errors, f"{name}: QML errors: {errors[:3]}")
    return QImage(str(out))


def count(img: QImage, box: tuple[int, int, int, int], test) -> int:
    x0, y0, x1, y1 = box
    return sum(1 for x in range(x0, x1, 4) for y in range(y0, y1, 4) if test(img.pixelColor(x, y)))


with tempfile.TemporaryDirectory() as tmp:
    tmp = Path(tmp)
    img = shot(tmp, "discover")
    if not img.isNull():
        # The editorial card: deep blue into violet across the top of the page.
        card = count(img, (400, 190, 1280, 440), lambda c: c.blue() > 100 and c.blue() > c.green() + 40 and c.lightness() < 170)
        check(card > 6000, f"Discover: expected the Mac apps card, found {card} of its pixels")
        # Shelves below it: GET pills in the accent.
        pills = count(img, (740, 540, 1290, 840), lambda c: c.blue() > 200 and c.red() < 60)
        check(pills > 20, f"Discover: expected GET buttons on the shelves, found {pills} accent pixels")
    img = shot(tmp, "mac", "GG_STORE_PAGE=mac")
    if not img.isNull():
        # Darling isn't installed here: the Set Up… button, in the accent.
        setup = count(img, (1150, 200, 1280, 250), lambda c: c.blue() > 200 and c.red() < 60)
        check(setup > 20, f"Mac Apps: expected the Set Up button, found {setup} accent pixels")
        tiles = count(img, (390, 340, 460, 840), lambda c: c.hsvSaturation() > 120)
        check(tiles > 300, f"Mac Apps: expected app tiles down the page, found {tiles} coloured pixels")
    img = shot(tmp, "detail", "GG_STORE_APP=iina")
    if not img.isNull():
        icon = count(img, (400, 130, 520, 250), lambda c: c.hsvSaturation() > 100)
        check(icon > 500, f"an app's page: expected its large icon, found {icon} pixels")

qml = (ROOT / "apps/software.qml").read_text()
for needle, what in [("software/macapps.py", "the store talks to the Mac backend"), ("darling-setup.sh", "Set Up runs the Darling setup"),
                     ('"no-darling"', "opening before Darling is set up asks to set it up"), ("store.queue", "Update All goes through every update")]:
    check(needle in qml, what)
check("7zip" in (ROOT / "distro/archiso/packages.x86_64").read_text().split(), "7-Zip is on the image, for .dmg downloads")

if failures:
    print("\n".join("FAIL " + f for f in failures), file=sys.stderr)
    raise SystemExit(1)
print("App Store: Discover, Mac Apps and an app's page draw; Mac apps and Darling setup wired")
