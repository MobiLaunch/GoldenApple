#!/usr/bin/env python3
"""Files' Quick Look and keyboard, through the preview harness (tools/preview).

Quick Look opens on the selected item (GG_FILES_QUICKLOOK=1, as Space would)
and shows a picture as itself, a text file as its text and anything else as
its icon and kind. The keys are wired as in Finder: Space and ⌘Y for Quick
Look, arrows to move, Return to rename, ⌘O/⌘↓ to open, ⌘↑ for the enclosing
folder, ⌘⌫ to the Trash."""
from __future__ import annotations

from pathlib import Path
import re
import subprocess
import sys
import tempfile

from PySide6.QtGui import QImage

ROOT = Path(__file__).resolve().parents[1]
PREVIEW = ROOT / "tools/preview/preview.py"
HOME = ROOT / "tools/preview/cache/home"
failures: list[str] = []


def check(cond: bool, what: str) -> None:
    if not cond:
        failures.append(what)


def shot(tmp: Path, name: str, folder: str, item: str) -> QImage:
    out = tmp / f"{name}.png"
    proc = subprocess.run([sys.executable, str(PREVIEW), "app", "apps/files.qml", "--wait", "1200",
                           "--env", f"GG_FILES_PATH={HOME / folder}", f"--env=GG_FILES_SELECT={HOME / folder / item}",
                           "--env", "GG_FILES_QUICKLOOK=1", "-v", "-o", str(out)],
                          capture_output=True, text=True, timeout=180, cwd=ROOT)
    errors = [l for l in proc.stderr.splitlines() if re.search(r"QuickLook\.qml.*(Error|TypeError|ReferenceError|Unable)", l)]
    check(proc.returncode == 0 and out.exists(), f"{name}: preview failed: {proc.stderr[-400:]}")
    check(not errors, f"{name}: QML errors: {errors[:3]}")
    return QImage(str(out))


with tempfile.TemporaryDirectory() as tmp:
    tmp = Path(tmp)
    # The harness writes the sample home on first run; make sure it exists.
    subprocess.run([sys.executable, str(PREVIEW), "app", "apps/files.qml", "--wait", "100", "-o", str(tmp / "warm.png")],
                   capture_output=True, timeout=180, cwd=ROOT)

    # A picture: the sunset's orange sky fills the middle of the window.
    img = shot(tmp, "image", "Pictures", "Sunset over Tiburon.png")
    if not img.isNull():
        c = img.pixelColor(img.width() // 2, int(img.height() * 0.36))
        check(c.red() > 220 and 120 < c.green() < 200 and c.blue() < 140, f"picture: expected the orange sky, got {c.name()}")

    # Text: the brief's lines, below the row of icons, where the folder is empty.
    img = shot(tmp, "text", "Documents", "CitronOS brief.md")
    if not img.isNull():
        dark = sum(1 for x in range(360, 900, 3) for y in range(340, 460, 3) if img.pixelColor(x, y).lightness() < 90)
        check(dark > 40, f"text: expected the brief's text in the preview, found {dark} dark pixels")

    # Anything else: a light card in the middle, with the window dimmed around it.
    img = shot(tmp, "other", "Downloads", "inter-4.1.zip")
    if not img.isNull():
        card, around = img.pixelColor(img.width() // 2, int(img.height() * 0.4)), img.pixelColor(1150, 720)
        check(card.lightness() > 200, f"other: expected the light card in the middle, got {card.name()}")
        check(around.lightness() < card.lightness() - 8, f"other: expected the window dimmed around the card, got {around.name()}")

    # The Trash and Recents are views of their own: the sample Trash's picture
    # (IMG_0412.png) comes first; Recents lists files, newest first.
    for view, what in (("trash:", "Trash"), ("recents:", "Recents")):
        out = tmp / f"{what}.png"
        proc = subprocess.run([sys.executable, str(PREVIEW), "app", "apps/files.qml", "--wait", "900",
                               "--env", f"GG_FILES_PATH={view}", "-o", str(out)],
                              capture_output=True, text=True, timeout=180, cwd=ROOT)
        img = QImage(str(out))
        check(proc.returncode == 0 and not img.isNull(), f"{what}: preview failed")
        if not img.isNull():
            # The first item's icon (in the grid's first cell) is drawn, not "Folder Unavailable".
            colourful = sum(1 for x in range(465, 515, 2) for y in range(185, 235, 2)
                            if img.pixelColor(x, y).hsvSaturation() > 80 or img.pixelColor(x, y).lightness() < 200)
            check(colourful > 30, f"{what}: expected its first item in the grid, found {colourful} icon pixels")

files = (ROOT / "apps/files.qml").read_text()
for needle, what in [("Qt.Key_Space", "Space toggles Quick Look"), ("Qt.Key_Y", "⌘Y toggles Quick Look"),
                     ("moveSelection(-columns, event.modifiers)", "↑ moves up a row"), ("moveSelection(columns, event.modifiers)", "↓ moves down a row"),
                     ("Qt.Key_Return", "Return renames"), ("Qt.Key_End", "⌘↓ opens"),
                     ("enclosingFolder()", "⌘↑ goes up"), ("Qt.Key_Backspace", "⌘⌫ moves to the Trash"),
                     ("QuickLook {", "Files has Quick Look"), ("Drag.dragType: Drag.Automatic", "items drag out"),
                     ("files.dropOn(drop, cell.modelData.path)", "folders take drops"), ("files.dropOn(drop, place.modelData.path)", "the sidebar takes drops"),
                     ('path: "trash:"', "the sidebar has the Trash"), ('path: "recents:"', "the sidebar has Recents"), ('text: "Quick Look", shortcut: "Space"', "the context menu offers Quick Look")]:
    check(needle in files, what)

if failures:
    print("\n".join("FAIL " + f for f in failures), file=sys.stderr)
    raise SystemExit(1)
print("Quick Look: pictures, text and other files preview; Finder's keys are wired")
