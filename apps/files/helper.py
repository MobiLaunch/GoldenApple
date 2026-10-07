#!/usr/bin/env python3
"""Filesystem backend for CitronOS Files."""
from __future__ import annotations

import json
import mimetypes
import os
import pathlib
import shutil
import stat
import subprocess
import sys
import time
from datetime import datetime
from urllib.parse import quote, unquote, urlparse
import xml.etree.ElementTree as ET


def result(ok: bool = True, **payload: object) -> int:
    print(json.dumps({"ok": ok, **payload}, separators=(",", ":")))
    return 0 if ok else 1


def icon_for(path: pathlib.Path, mime: str, folder: bool | None = None) -> str:
    if path.is_dir() if folder is None else folder:
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
    # One stat a file (a broken link: the link itself), not one per question.
    try:
        st = path.stat()
    except OSError:
        st = path.lstat()
    folder = stat.S_ISDIR(st.st_mode)
    mime = "inode/directory" if folder else (mimetypes.guess_type(path.name)[0] or "application/octet-stream")
    return {
        "name": path.name or str(path),
        "path": str(path),
        "folder": folder,
        "size": 0 if folder else int(st.st_size),
        "modified": int(st.st_mtime),
        "mime": mime,
        "icon": icon_for(path, mime, folder),
        "hidden": path.name.startswith("."),
    }


# ---------------------------------------------------------------- Trash
# The freedesktop.org Trash (what gio, Nautilus and the Dock use): the item in
# Trash/files, and in Trash/info a .trashinfo with where it came from and when.
def trash_dir() -> pathlib.Path:
    return pathlib.Path(os.environ.get("XDG_DATA_HOME") or pathlib.Path.home() / ".local/share") / "Trash"


def trash_info(name: str) -> tuple[str, int]:
    origin, deleted = "", 0
    try:
        for line in (trash_dir() / "info" / f"{name}.trashinfo").read_text().splitlines():
            if line.startswith("Path="):
                origin = unquote(line[5:])
            elif line.startswith("DeletionDate="):
                deleted = int(datetime.fromisoformat(line[13:]).timestamp())
    except (OSError, ValueError):
        pass
    return origin, deleted


def list_trash(query: str = "") -> int:
    files = trash_dir() / "files"
    q = query.strip().casefold()
    rows = []
    for child in sorted(files.iterdir()) if files.is_dir() else []:
        origin, deleted = trash_info(child.name)
        shown = pathlib.Path(origin).name if origin else child.name
        if q and q not in shown.casefold():
            continue
        try:
            row = describe(child)
        except OSError:
            continue
        row.update(name=shown, trashName=child.name, origin=origin, deleted=deleted)
        rows.append(row)
    rows.sort(key=lambda r: -int(r.get("deleted") or r["modified"]))
    return result(True, path="trash:", parent="", entries=rows)


def unique(target: pathlib.Path) -> pathlib.Path:
    """target, or "name 2.ext", "name 3.ext"… if that's taken, as Finder names copies."""
    if not target.exists() and not target.is_symlink():
        return target
    stem, suffix = (target.name, "") if target.is_dir() else (target.stem, target.suffix)
    n = 2
    while True:
        candidate = target.with_name(f"{stem} {n}{suffix}")
        if not candidate.exists() and not candidate.is_symlink():
            return candidate
        n += 1


def trash(*raws: str) -> int:
    base = trash_dir()
    (base / "files").mkdir(parents=True, exist_ok=True)
    (base / "info").mkdir(parents=True, exist_ok=True)
    for raw in raws:
        path = pathlib.Path(raw).expanduser().absolute()
        if not path.exists() and not path.is_symlink():
            return result(False, error=f"“{path.name}” is no longer there.")
        # Another disk has its own trash; gio knows where.
        try:
            same = path.lstat().st_dev == base.stat().st_dev
        except OSError:
            same = False
        if not same:
            try:
                p = subprocess.run(["gio", "trash", str(path)], text=True, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, timeout=120)
            except subprocess.TimeoutExpired:
                return result(False, error=f"Moving “{path.name}” to the Trash took too long. The disk may not be answering.")
            if p.returncode:
                return result(False, error=p.stdout.strip() or f"“{path.name}” couldn't be moved to the Trash.")
            continue
        name = unique(base / "files" / path.name).name
        info = base / "info" / f"{name}.trashinfo"
        info.write_text("[Trash Info]\nPath=%s\nDeletionDate=%s\n" % (quote(str(path)), datetime.now().strftime("%Y-%m-%dT%H:%M:%S")))
        try:
            os.rename(path, base / "files" / name)
        except OSError as exc:
            info.unlink(missing_ok=True)
            return result(False, error=str(exc))
    return result(True)


def put_back(*names: str) -> int:
    base = trash_dir()
    for name in names:
        item = base / "files" / name
        origin, _ = trash_info(name)
        if not item.exists() and not item.is_symlink():
            return result(False, error="That item is no longer in the Trash.")
        if not origin:
            return result(False, error=f"Files doesn't know where “{name}” came from.")
        target = unique(pathlib.Path(origin))
        try:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(item), str(target))
        except OSError as exc:
            return result(False, error=str(exc))
        (base / "info" / f"{name}.trashinfo").unlink(missing_ok=True)
    return result(True)


def empty_trash() -> int:
    base = trash_dir()
    for sub in ("files", "info"):
        folder = base / sub
        for child in folder.iterdir() if folder.is_dir() else []:
            try:
                if child.is_dir() and not child.is_symlink():
                    shutil.rmtree(child)
                else:
                    child.unlink()
            except OSError as exc:
                return result(False, error=str(exc))
    # The Trash on other disks too, where gio can reach it.
    try:
        emptied = subprocess.run(["gio", "trash", "--empty"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)
        if emptied.returncode:
            return result(True, warning="Home Trash emptied. Trash on other disks could not be emptied.")
    except FileNotFoundError:
        # Home Trash was emptied above; gio is only needed for other mounts.
        return result(True, warning="Home Trash emptied. Other disks require gio to empty their Trash.")
    except (OSError, subprocess.TimeoutExpired):
        return result(False, error="Home Trash was emptied, but Trash on other disks could not be reached.")
    return result(True)


# ---------------------------------------------------------------- Recents
# What you've opened lately (recently-used.xbel, which GTK and Qt apps keep),
# then what's changed lately in your folders, newest first.
def list_recents(query: str = "") -> int:
    home = pathlib.Path.home()
    seen: dict[str, int] = {}
    xbel = pathlib.Path(os.environ.get("XDG_DATA_HOME") or home / ".local/share") / "recently-used.xbel"
    try:
        for bm in ET.parse(xbel).getroot().iter("bookmark"):
            href = bm.get("href", "")
            if not href.startswith("file://"):
                continue
            stamp = bm.get("visited") or bm.get("modified") or ""
            try:
                when = int(datetime.fromisoformat(stamp.replace("Z", "+00:00")).timestamp())
            except ValueError:
                when = 0
            seen[unquote(urlparse(href).path)] = when
    except (OSError, ET.ParseError):
        pass
    cutoff = time.time() - 30 * 86400
    for top in ("Desktop", "Documents", "Downloads", "Pictures", "Music", "Videos"):
        root = home / top
        for dirpath, dirnames, filenames in os.walk(root) if root.is_dir() else []:
            dirnames[:] = [d for d in dirnames if not d.startswith(".")]
            if dirpath.count(os.sep) - str(root).count(os.sep) >= 3:
                dirnames[:] = []
            for f in filenames:
                if f.startswith("."):
                    continue
                full = os.path.join(dirpath, f)
                try:
                    mtime = int(os.stat(full).st_mtime)
                except OSError:
                    continue
                if mtime >= cutoff:
                    seen[full] = max(seen.get(full, 0), mtime)
    q = query.strip().casefold()
    rows = []
    # Newest first; files from the same second in a steady order, not the
    # order the disk happens to list them in.
    for path, when in sorted(seen.items(), key=lambda kv: (-kv[1], kv[0])):
        p = pathlib.Path(path)
        if not p.is_file() or (q and q not in p.name.casefold()):
            continue
        row = describe(p)
        row["used"] = when
        rows.append(row)
        if len(rows) >= 80:
            break
    return result(True, path="recents:", parent="", entries=rows)


# ---------------------------------------------------------------- drag and drop
def drop(dest_raw: str, mode: str, *raws: str) -> int:
    """Items dropped on a folder. As in Finder: on the same disk they move, to
    another disk they're copied; mode "copy" always copies."""
    dest = pathlib.Path(dest_raw).expanduser().resolve()
    if not dest.is_dir():
        return result(False, error="That folder is no longer available.")
    done = []
    for raw in raws:
        src = pathlib.Path(raw).expanduser().absolute()
        if not src.exists() and not src.is_symlink():
            return result(False, error=f"“{src.name}” is no longer there.")
        if src.parent.resolve() == dest and mode != "copy":
            continue                       # dropped where it already is
        if src.is_dir() and (dest == src.resolve() or src.resolve() in dest.parents):
            return result(False, error=f"“{src.name}” can't be moved into itself.")
        copy = mode == "copy" or src.lstat().st_dev != dest.stat().st_dev
        target = unique(dest / src.name)
        try:
            if copy:
                if src.is_dir() and not src.is_symlink():
                    shutil.copytree(src, target, symlinks=True)
                else:
                    shutil.copy2(src, target, follow_symlinks=False)
            else:
                shutil.move(str(src), str(target))
        except OSError as exc:
            return result(False, error=str(exc))
        done.append(str(target))
    return result(True, action="copy" if mode == "copy" else "move", paths=done)


def list_dir(raw: str, query: str = "") -> int:
    if raw == "trash:" or pathlib.Path(raw).expanduser() == trash_dir() / "files":
        return list_trash(query)
    if raw == "recents:":
        return list_recents(query)
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
    if cmd == "trash" and len(sys.argv) >= 3:
        return trash(*sys.argv[2:])
    if cmd == "put-back" and len(sys.argv) >= 3:
        return put_back(*sys.argv[2:])
    if cmd == "empty-trash":
        return empty_trash()
    if cmd == "drop" and len(sys.argv) >= 5:
        return drop(sys.argv[2], sys.argv[3], *sys.argv[4:])
    if cmd == "open" and len(sys.argv) == 3:
        return open_item(sys.argv[2])
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
