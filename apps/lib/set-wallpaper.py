#!/usr/bin/env python3
"""Make any picture the wallpaper (Settings › Wallpaper, Photos' Set as
Wallpaper).

    set-wallpaper.py PATH               copy it into your wallpapers and use it
    set-wallpaper.py --copy-only PATH   copy it, print where, and leave the choice

The picture is copied into ~/.local/share/backgrounds/golden-gate, so the
wallpaper stays when the original is moved or deleted (and it joins your
wallpapers in Settings); the same picture chosen twice is kept once. Formats
the shell can't draw (HEIC, AVIF) are converted to PNG with ffmpeg. Prints
the wallpaper's path; exits non-zero, saying why, if it can't be used."""
from __future__ import annotations

import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys

DRAWN = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".gif", ".tif", ".tiff"}
CONVERTED = {".heic", ".heif", ".avif"}


def wallpapers() -> pathlib.Path:
    data = pathlib.Path(os.environ.get("XDG_DATA_HOME") or pathlib.Path.home() / ".local/share")
    return data / "backgrounds/golden-gate"


def adopt(source: pathlib.Path) -> pathlib.Path:
    if not source.is_file():
        raise SystemExit(f"{source} isn't a file")
    ext = source.suffix.lower()
    if ext not in DRAWN | CONVERTED:
        raise SystemExit(f"{source.name} isn't a picture that can be a wallpaper")
    folder = wallpapers()
    folder.mkdir(parents=True, exist_ok=True)
    # Already one of your wallpapers: used as it is.
    try:
        if source.resolve().parent == folder.resolve():
            return source.resolve()
    except OSError:
        pass
    digest = hashlib.sha1()
    with source.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            digest.update(block)
    stem = "".join(c if c.isalnum() or c in "-_ " else "-" for c in source.stem).strip() or "Wallpaper"
    target = folder / f"{stem}-{digest.hexdigest()[:8]}{'.png' if ext in CONVERTED else ext}"
    if target.exists():
        return target
    partial = target.with_name("." + target.name + ".part")
    try:
        if ext in CONVERTED:
            if not shutil.which("ffmpeg"):
                raise SystemExit(f"{source.name} needs ffmpeg to be converted")
            done = subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", str(source),
                                   "-frames:v", "1", "-f", "image2", "-c:v", "png", str(partial)],
                                  capture_output=True, text=True)
            if done.returncode != 0 or not partial.exists():
                raise SystemExit(f"{source.name} couldn't be converted: {done.stderr.strip()[:200]}")
        else:
            shutil.copyfile(source, partial)
        os.replace(partial, target)
    finally:
        partial.unlink(missing_ok=True)
    return target


def choose(path: pathlib.Path) -> None:
    # Through gg-pref, the one writer of desktop.json; from a checkout, its
    # source beside this one.
    command = shutil.which("gg-pref")
    args = [command] if command else [sys.executable, str(pathlib.Path(__file__).resolve().parents[1] / "setup/pref-helper.py")]
    done = subprocess.run(args + ["wallpaper", json.dumps(str(path))], capture_output=True, text=True)
    if done.returncode != 0:
        raise SystemExit(done.stderr.strip() or "the wallpaper couldn't be saved")


def main(argv: list[str]) -> int:
    copy_only = "--copy-only" in argv
    paths = [a for a in argv if a != "--copy-only"]
    if len(paths) != 1:
        raise SystemExit(__doc__.strip().splitlines()[2])
    wallpaper = adopt(pathlib.Path(paths[0]).expanduser())
    if not copy_only:
        choose(wallpaper)
    print(wallpaper)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
