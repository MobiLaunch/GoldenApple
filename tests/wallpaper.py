#!/usr/bin/env python3
"""Any picture can be the wallpaper: lib/set-wallpaper.py copies it into your
wallpapers (so it stays when the original goes), keeps the same picture once,
refuses what isn't a picture, and chooses it through desktop.json; Settings ›
Wallpaper lists your photos and offers any picture on the computer; Photos
has Set as Wallpaper, in its … menu and on a right-click."""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "apps/lib/set-wallpaper.py"
failures: list[str] = []


def check(cond: bool, what: str) -> None:
    if not cond:
        failures.append(what)


def helper(env: dict, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(HELPER), *args], env=env, capture_output=True, text=True, timeout=60)


with tempfile.TemporaryDirectory() as t:
    home = Path(t)
    env = dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / ".config"), XDG_DATA_HOME=str(home / ".local/share"),
               PATH="/usr/bin:/bin")       # no gg-pref: the helper uses pref-helper.py beside it
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    from PySide6.QtGui import QGuiApplication, QImage, QColor
    app = QGuiApplication([])
    photo = home / "Pictures/Trip/Beach day.png"
    photo.parent.mkdir(parents=True)
    img = QImage(64, 40, QImage.Format_RGB32)
    img.fill(QColor("#3478f6"))
    img.save(str(photo))
    walls = home / ".local/share/backgrounds/golden-gate"
    prefs = home / ".config/golden-gate/desktop.json"

    p = helper(env, str(photo))
    check(p.returncode == 0, f"a photo becomes the wallpaper ({p.stderr.strip()})")
    chosen = json.loads(prefs.read_text()).get("wallpaper") if prefs.exists() else None
    copies = list(walls.glob("*.png")) if walls.exists() else []
    check(len(copies) == 1 and chosen == str(copies[0]), f"it's copied into your wallpapers and chosen: {chosen} {copies}")
    check(bool(copies) and copies[0].read_bytes() == photo.read_bytes(), "the copy is the picture itself")
    check(p.stdout.strip() == chosen, "the helper says where the wallpaper is")

    photo.unlink()
    check(bool(copies) and copies[0].exists(), "the wallpaper stays when the photo is deleted")
    img.save(str(photo))
    helper(env, str(photo))
    check(len(list(walls.glob("*.png"))) == 1, "the same picture chosen twice is kept once")

    other = home / "Pictures/Other.jpg"
    img.fill(QColor("#ff9f0a"))
    img.save(str(other))
    p = helper(env, "--copy-only", str(other))
    check(p.returncode == 0 and Path(p.stdout.strip()).exists(), "--copy-only copies it")
    check(json.loads(prefs.read_text())["wallpaper"] == chosen, "--copy-only leaves the wallpaper as it was")

    own = Path(p.stdout.strip())
    p = helper(env, str(own))
    check(p.returncode == 0 and p.stdout.strip() == str(own.resolve()), "one of your wallpapers is used as it is")
    check(len(list(walls.iterdir())) == 2, "…without another copy")

    note = home / "notes.txt"
    note.write_text("not a picture")
    p = helper(env, str(note))
    check(p.returncode != 0 and "picture" in (p.stderr + p.stdout), f"something that isn't a picture is refused ({p.stderr.strip()})")
    check(json.loads(prefs.read_text())["wallpaper"] == str(own.resolve()), "…and the wallpaper is unchanged")
    p = helper(env, str(home / "missing.png"))
    check(p.returncode != 0, "a missing file is refused")

# Settings › Wallpaper: your photos, and any picture on the computer.
pane = (ROOT / "apps/settings/panes/WallpaperPane.qml").read_text()
check('objectName: "photosWallpapers"' in pane and "GG_PHOTOS_DIRS" in pane, "Settings lists the Photos library's pictures")
check("function browse(" in pane and '"Choose…"' in pane, "Settings can choose any picture on the computer")
check("set-wallpaper.py" in pane and '"--copy-only"' in pane, "Settings copies a picture from elsewhere into your wallpapers first")
if os.environ.get("CI") or subprocess.run(["sh", "-c", "command -v xvfb-run"], capture_output=True).returncode == 0:
    with tempfile.TemporaryDirectory() as t:
        out = Path(t) / "pane.png"
        r = subprocess.run([sys.executable, str(ROOT / "tools/preview/preview.py"), "app", "apps/settings.qml",
                            "--env", "GG_SETTINGS_PANE=wallpaper", "--wait", "1500",
                            "--require-object", "photosWallpapers", "-o", str(out)],
                           cwd=ROOT, capture_output=True, text=True, timeout=200,
                           env=dict(os.environ, QT_QPA_PLATFORM=os.environ.get("QT_QPA_PLATFORM", "offscreen")))
        check(r.returncode == 0 and out.exists(), f"the Wallpaper pane shows your photos: {r.stderr.strip()[-400:]}")
        r = subprocess.run([sys.executable, str(ROOT / "tools/preview/preview.py"), "app", "apps/settings.qml",
                            "--env", "GG_SETTINGS_PANE=wallpaper", "--env", f"GG_WALLPAPER_FOLDER={ROOT / 'tools/preview/cache/home/Pictures'}",
                            "--wait", "1500", "--require-object", "chooseAPicture", "-o", str(out)],
                           cwd=ROOT, capture_output=True, text=True, timeout=200,
                           env=dict(os.environ, QT_QPA_PLATFORM=os.environ.get("QT_QPA_PLATFORM", "offscreen")))
        check(r.returncode == 0, f"Choose… browses the computer's folders: {r.stderr.strip()[-400:]}")
        check("depends on non-bindable" not in r.stderr, "no binding warnings")

# Photos: Set as Wallpaper, in the … menu and on a right-click.
photos = (ROOT / "apps/photos.qml").read_text()
check(re.search(r'text: "Set as Wallpaper".*setWallpaper\(it\)', photos) is not None, "Photos' menu has Set as Wallpaper")
check("lib/set-wallpaper.py" in photos, "Photos sets it through the same helper")
check(photos.count("acceptedButtons: Qt.RightButton") >= 2, "a right-click on a photo, in the grid or open, has its menu")
check(photos.count("app.itemMenu(") >= 3, "the … menu and the right-click show the same menu")

for f in failures:
    print("FAIL", f)
if not failures:
    print("Wallpaper: any picture or photo, copied into your wallpapers and chosen; Settings lists your photos and any picture; Photos has Set as Wallpaper")
sys.exit(1 if failures else 0)
