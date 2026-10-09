#!/usr/bin/env python3
"""Safe local Music playlist editing. Existing M3U/M3U8 files are supported.

Commands: list, deleted, restore, create, rename, delete, add, remove, move, duplicate.
Mutations accept one JSON object on stdin and return the latest playlist view.
Playlist files stay in the user's Music/Playlists folder, and the audio files
themselves are never modified or removed.
"""
from __future__ import annotations

import contextlib
import errno
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile
import time


def music_dir():
    return Path(os.environ.get("GG_MUSIC_DIR") or os.environ.get("XDG_MUSIC_DIR")
                or Path.home() / "Music").expanduser().resolve()


def folder():
    return music_dir() / "Playlists"


def output(ok, **other):
    print(json.dumps({"ok": ok, **other}, ensure_ascii=False))
    return 0 if ok else 1


def validate_name(value):
    if not isinstance(value, str):
        raise ValueError("Enter a playlist name.")
    name = value.strip()
    if not name or len(name) > 80 or name in (".", ".."):
        raise ValueError("Choose a playlist name of 1–80 characters.")
    if name.startswith(".") or name.endswith(".") or any(c in name for c in "/\\:\x00\r\n"):
        raise ValueError("Playlist names cannot contain path separators, colons, or line breaks.")
    if any(ord(c) < 32 for c in name):
        raise ValueError("Playlist names cannot contain control characters.")
    if name.lower().endswith((".m3u", ".m3u8")):
        raise ValueError("Leave the .m3u8 extension out of the playlist name.")
    return name


def playlist_path(value, must_exist=True):
    if not isinstance(value, str):
        raise ValueError("Choose a playlist.")
    path = Path(value)
    root = folder().resolve()
    if not path.is_absolute() or path.parent.resolve() != root or path.suffix.lower() not in (".m3u", ".m3u8"):
        raise ValueError("That playlist is outside your Music library.")
    if must_exist and (not path.is_file() or path.is_symlink()):
        raise ValueError("The playlist is missing or is a symbolic link.")
    return path


def available(name, except_path=None):
    folded = name.casefold()
    for path in candidates():
        if except_path and path == except_path:
            continue
        if path.stem.casefold() == folded:
            raise ValueError("A playlist with that name already exists.")


def deleted_folder():
    return folder() / ".Deleted"


def deleted_records():
    root = deleted_folder()
    if root.is_symlink():
        raise ValueError("Deleted playlist directory must not be a symlink.")
    if not root.is_dir():
        return []
    records = []
    for path in root.iterdir():
        match = re.fullmatch(r"(.+\.m3u8?)\.(\d{13,20})\.bak", path.name, re.IGNORECASE)
        if not match or path.is_symlink() or not path.is_file():
            continue
        records.append({"path": str(path), "name": Path(match.group(1)).stem,
                        "filename": match.group(1), "deletedAt": int(match.group(2)) // 1000000,
                        "revision": revision(path)})
    return sorted(records, key=lambda item: item["deletedAt"], reverse=True)


def deleted_path(value):
    if not isinstance(value, str):
        raise ValueError("Choose a deleted playlist.")
    path = Path(value)
    root = deleted_folder()
    if root.is_symlink() or not path.is_absolute() or path.parent != root:
        raise ValueError("That deleted playlist is outside the library.")
    if not re.fullmatch(r".+\.m3u8?\.\d{13,20}\.bak", path.name, re.IGNORECASE):
        raise ValueError("That is not a recoverable playlist archive.")
    if not path.is_file() or path.is_symlink():
        raise ValueError("The deleted playlist is missing or unsafe to restore.")
    return path


def candidates():
    root = folder()
    if not root.is_dir():
        return []
    return sorted((p for p in root.iterdir() if p.suffix.lower() in (".m3u", ".m3u8")
                   and p.is_file() and not p.is_symlink()),
                  key=lambda p: (p.stem.casefold(), p.suffix.casefold(), p.name.casefold()))


def revision(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parse_playlist(path):
    """Retain EXTINF and unknown directives with their following track."""
    rows = []
    pending = []
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        value = line.strip()
        if not value:
            continue
        if value.startswith("#"):
            pending.append(line)
            continue
        track = Path(value)
        absolute = track if track.is_absolute() else (path.parent / track)
        rows.append({"path": str(absolute.resolve(strict=False)), "lines":pending + [line]})
        pending = []
    return rows, pending


def view():
    playlists = []
    for item in candidates():
        try:
            rows, _ = parse_playlist(item)
            playlists.append({"path":str(item), "name":item.stem,
                              "paths":[r["path"] for r in rows],
                              "count":len(rows), "revision":revision(item)})
        except (OSError, UnicodeError):
            # Corrupt or unreadable user playlists are not changed or hidden.
            playlists.append({"path":str(item), "name":item.stem,
                              "paths":[], "count":0, "error":"Could not read this playlist."})
    return playlists


@contextlib.contextmanager
def locked():
    root = folder()
    root.mkdir(parents=True, exist_ok=True)
    lock_path = root / ".gg-playlists.lock"
    with lock_path.open("a+") as fd:
        fcntl.flock(fd, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(fd, fcntl.LOCK_UN)


def publish_exclusively(source, dest):
    """Create without clobbering on hard-link and non-hard-link filesystems.

    A hard link gives atomic visibility. On filesystems without hard-link
    support (some removable disks), copy to an exclusive target and remove
    it on error, keeping the original until the write is successful.
    """
    try:
        os.link(source, dest)
        return
    except OSError as exc:
        if exc.errno not in (errno.EPERM, errno.EOPNOTSUPP, errno.EMLINK):
            raise
    fd = os.open(dest, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, "wb") as target, open(source, "rb") as original:
            shutil.copyfileobj(original, target)
            target.flush()
            os.fsync(target.fileno())
    except Exception:
        Path(dest).unlink(missing_ok=True)
        raise


def atomic_text(path, text, replace=False):
    fd, temp = tempfile.mkstemp(prefix=".playlist-", suffix=".tmp", dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as stream:
            stream.write(text)
            stream.flush()
            os.fsync(stream.fileno())
        if replace and path.exists():
            # Make a fresh exclusive backup; a .bak symlink must never redirect
            # the copy onto a file outside the Music directory.
            backup = path.with_name(path.name + ".bak")
            if backup.exists() or backup.is_symlink():
                backup = path.with_name(path.name + "." + str(time.time_ns()) + ".bak")
            with open(path, "rb") as original:
                backup_fd = os.open(backup, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                with os.fdopen(backup_fd, "wb") as recovery:
                    shutil.copyfileobj(original, recovery)
                    recovery.flush()
                    os.fsync(recovery.fileno())
        if replace:
            os.replace(temp, path)
        else:
            # Publish an entirely new playlist without ever replacing
            # another process's newly created file.
            publish_exclusively(temp, path)
    finally:
        Path(temp).unlink(missing_ok=True)


def serialize(rows, trailing):
    # Preserve EXTINF tags and unknown per-track comments when rearranging.
    # An unstructured playlist is still valid M3U8.
    lines = ["#EXTM3U"]
    for r in rows:
        block = [v for v in r["lines"] if v.strip() != "#EXTM3U"]
        lines.extend(block)
    lines.extend(v for v in trailing if v.strip() != "#EXTM3U")
    return "\n".join(lines) + "\n"


def checked_track(value):
    if not isinstance(value, str) or not value or len(value) > 4096 or any(c in value for c in "\x00\r\n"):
        raise ValueError("Select a valid music file from the library.")
    path = Path(value)
    if not path.is_absolute() or not path.is_file():
        raise ValueError("The selected track is missing.")
    return str(path.resolve())


def execute(command, data):
    if command == "list":
        return {"playlists":view()}
    if command == "deleted":
        return {"deleted":deleted_records()}
    if command == "restore":
        source = deleted_path(data.get("path"))
        if data.get("expected") != revision(source):
            raise ValueError("This deleted playlist changed. Reopen Recently Deleted.")
        filename = re.fullmatch(r"(.+\.m3u8?)\.\d{13,20}\.bak",
                                source.name, re.IGNORECASE).group(1)
        base = Path(filename).stem
        extension = Path(filename).suffix
        target = folder() / filename
        if target.exists() or target.is_symlink() or any(
                p.stem.casefold() == base.casefold() for p in candidates()):
            # A name conflict never overwrites an active playlist.
            for n in range(1, 1001):
                postfix = " Restored" if n == 1 else " Restored " + str(n)
                stem = base[:80-len(postfix)].rstrip() + postfix
                target = folder() / (stem + extension)
                if not (target.exists() or target.is_symlink()) and not any(
                        p.stem.casefold() == stem.casefold() for p in candidates()):
                    break
            else:
                raise ValueError("Could not find an unused name for the restored playlist.")
        publish_exclusively(source, target)
        source.unlink()
        return {"playlist":str(target), "playlists":view(), "deleted":deleted_records()}
    if command == "create":
        name = validate_name(data.get("name"))
        available(name)
        path = folder() / (name + ".m3u8")
        if path.exists() or path.is_symlink():
            raise ValueError("A playlist file already exists at that path.")
        atomic_text(path, "#EXTM3U\n")
        return {"playlist":str(path), "playlists":view()}
    path = playlist_path(data.get("path"))
    if data.get("expected") is not None and data["expected"] != revision(path):
        raise ValueError("This playlist changed in another window. Reload before editing.")
    if command == "delete":
        # Move to a recoverable folder rather than permanently destroying lists.
        trash = deleted_folder()
        if trash.is_symlink():
            raise ValueError("Deleted playlist directory must not be a symbolic link.")
        trash.mkdir(mode=0o700, exist_ok=True)
        destination = trash / (path.name + "." + str(time.time_ns()) + ".bak")
        publish_exclusively(path, destination)
        path.unlink()
        return {"playlists":view(), "deleted":deleted_records()}
    if command == "rename":
        name = validate_name(data.get("name"))
        available(name, except_path=path)
        new = folder() / (name + path.suffix)
        if new != path:
            if new.exists() or new.is_symlink():
                raise ValueError("A file already exists at the new playlist name.")
            publish_exclusively(path, new)
            path.unlink()
        return {"playlist":str(new), "playlists":view()}
    if command == "duplicate":
        base = validate_name(path.stem + " Copy")
        name = base
        n = 2
        while True:
            try:
                available(name)
                break
            except ValueError:
                name = validate_name(base + " " + str(n))
                n += 1
        new = folder() / (name + ".m3u8")
        # Original playlist contents remain byte-for-byte unchanged.
        if new.exists() or new.is_symlink():
            raise ValueError("A file already exists at the new playlist name.")
        atomic_text(new, path.read_text(encoding="utf-8-sig"))
        return {"playlist":str(new), "playlists":view()}
    rows, trailing = parse_playlist(path)
    if command == "add":
        music_file = checked_track(data.get("track"))
        if music_file in [row["path"] for row in rows]:
            raise ValueError("This song is already in the playlist.")
        rows.append({"path":music_file, "lines":[music_file]})
    elif command == "remove":
        i = data.get("index")
        if type(i) is not int or not 0 <= i < len(rows):
            raise ValueError("That song is no longer in the playlist.")
        rows.pop(i)
    elif command == "move":
        i, dest = data.get("index"), data.get("to")
        if type(i) is not int or type(dest) is not int or not (0 <= i < len(rows) and 0 <= dest < len(rows)):
            raise ValueError("The playlist order has changed; reload it.")
        row = rows.pop(i)
        rows.insert(dest, row)
    else:
        raise ValueError("Unsupported playlist operation.")
    atomic_text(path, serialize(rows, trailing), replace=True)
    return {"playlist":str(path), "playlists":view()}


def main():
    if len(sys.argv) != 2:
        return output(False, error="Choose a playlist operation.")
    cmd = sys.argv[1]
    if cmd not in ("list","deleted","restore","create","rename","delete","add","remove","move","duplicate"):
        return output(False, error="Unknown playlist operation.")
    try:
        if cmd == "list":
            return output(True, **execute(cmd, {}))
        if cmd == "deleted":
            with locked():
                return output(True, **execute(cmd, {}))
        request = json.load(sys.stdin)
        if not isinstance(request, dict):
            raise ValueError("Invalid playlist request.")
        with locked():
            return output(True, **execute(cmd, request))
    except (ValueError, OSError, UnicodeError, json.JSONDecodeError) as exc:
        return output(False, error=str(exc))


if __name__ == "__main__":
    raise SystemExit(main())
