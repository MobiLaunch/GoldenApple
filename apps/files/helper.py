#!/usr/bin/env python3
"""Filesystem backend for Golden Gate Files."""
from __future__ import annotations

import json
import mimetypes
import os
import pathlib
import shutil
import subprocess
import sys
import time


def result(ok: bool = True, **payload: object) -> int:
    print(json.dumps({"ok": ok, **payload}, separators=(",", ":")))
    return 0 if ok else 1


def icon_for(path: pathlib.Path, mime: str) -> str:
    if path.is_dir():
        return "folder"
    if mime.startswith("image/"):
        return "image-x-generic"
    if mime.startswith("video/"):
        return "video-x-generic"
    if mime.startswith("audio/"):
        return "audio-x-generic"
    if mime in {"application/pdf"}:
        return "application-pdf"
    if mime.startswith("text/") or mime in {"application/json", "application/xml"}:
        return "text-x-generic"
    if os.access(path, os.X_OK):
        return "application-x-executable"
    return "application-octet-stream"


def describe(path: pathlib.Path) -> dict[str, object]:
    try:
        st = path.stat()
    except OSError:
        st = path.lstat()
    mime = "inode/directory" if path.is_dir() else (mimetypes.guess_type(path.name)[0] or "application/octet-stream")
    return {
        "name": path.name or str(path),
        "path": str(path),
        "folder": path.is_dir(),
        "size": 0 if path.is_dir() else int(st.st_size),
        "modified": int(st.st_mtime),
        "mime": mime,
        "icon": icon_for(path, mime),
        "hidden": path.name.startswith("."),
    }


def list_dir(raw: str, query: str = "") -> int:
    path = pathlib.Path(raw).expanduser().resolve()
    if not path.is_dir():
        return result(False, error="That folder is no longer available.", path=str(path))

    q = query.strip().casefold()
    rows: list[dict[str, object]] = []
    try:
        for child in path.iterdir():
            if child.name.startswith("."):
                continue
            if q and q not in child.name.casefold():
                continue
            try:
                rows.append(describe(child))
            except OSError:
                continue
    except OSError as exc:
        return result(False, error=str(exc), path=str(path))

    rows.sort(key=lambda r: (not bool(r["folder"]), str(r["name"]).casefold()))
    parent = str(path.parent) if path.parent != path else ""
    return result(True, path=str(path), parent=parent, entries=rows)


def mkdir(raw: str, name: str) -> int:
    parent = pathlib.Path(raw).expanduser().resolve()
    clean = name.strip().replace("/", "-")
    if not clean:
        return result(False, error="Enter a folder name.")
    target = parent / clean
    try:
        target.mkdir()
        return result(True, path=str(target))
    except Exception as exc:
        return result(False, error=str(exc))


def rename(raw: str, name: str) -> int:
    path = pathlib.Path(raw).expanduser().resolve()
    clean = name.strip().replace("/", "-")
    if not clean:
        return result(False, error="Enter a new name.")
    target = path.with_name(clean)
    try:
        path.rename(target)
        return result(True, path=str(target))
    except Exception as exc:
        return result(False, error=str(exc))


def trash(raw: str) -> int:
    path = pathlib.Path(raw).expanduser().resolve()
    p = subprocess.run(["gio", "trash", str(path)], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return result(p.returncode == 0, error=p.stdout.strip() if p.returncode else "")


def open_item(raw: str) -> int:
    path = pathlib.Path(raw).expanduser().resolve()
    try:
        subprocess.Popen(["xdg-open", str(path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        return result(True)
    except Exception as exc:
        return result(False, error=str(exc))


def main() -> int:
    if len(sys.argv) < 2:
        return 2
    cmd = sys.argv[1]
    if cmd == "list" and len(sys.argv) >= 3:
        return list_dir(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "")
    if cmd == "mkdir" and len(sys.argv) == 4:
        return mkdir(sys.argv[2], sys.argv[3])
    if cmd == "rename" and len(sys.argv) == 4:
        return rename(sys.argv[2], sys.argv[3])
    if cmd == "trash" and len(sys.argv) == 3:
        return trash(sys.argv[2])
    if cmd == "open" and len(sys.argv) == 3:
        return open_item(sys.argv[2])
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
