"""Writing files so they are either all old or all new, never half of each.

atomic_write writes beside the target, syncs it, renames it over, then syncs
the folder (so the rename survives a power cut too), and never leaves its
temporary file behind. New files are the owner's alone (0600) unless a mode
is given; a replaced file keeps its mode.
"""
from __future__ import annotations

import contextlib
import datetime
import fcntl
import json
import os
from pathlib import Path
import shutil
import tempfile

PRIVATE = 0o600


def _sync_folder(folder: Path) -> None:
    try:
        fd = os.open(folder, os.O_RDONLY | os.O_DIRECTORY)
    except OSError:
        return
    try:
        os.fsync(fd)
    except OSError:
        pass        # some filesystems can't sync a folder; the rename still happened
    finally:
        os.close(fd)


def atomic_write(path, data: bytes | str, mode: int | None = None, backup=None) -> None:
    """path becomes data, all at once. backup, if given, gets a copy of what
    was there first (itself written atomically)."""
    path = Path(path)
    raw = data.encode("utf-8") if isinstance(data, str) else bytes(data)
    path.parent.mkdir(parents=True, exist_ok=True)
    if mode is None:
        try:
            mode = path.stat().st_mode & 0o7777
        except FileNotFoundError:
            mode = PRIVATE
    if backup is not None and path.exists():
        atomic_write(backup, path.read_bytes(), mode=mode)
    fd, tmp = tempfile.mkstemp(prefix="." + path.name + ".", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as out:
            out.write(raw)
            out.flush()
            os.fchmod(out.fileno(), mode)
            os.fsync(out.fileno())
        os.replace(tmp, path)
    finally:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(tmp)
    _sync_folder(path.parent)


def atomic_json(path, value, mode: int | None = None, backup=None, indent: int | None = 1) -> None:
    text = json.dumps(value, ensure_ascii=False, indent=indent)
    atomic_write(path, text + "\n", mode=mode, backup=backup)


def read_json(path, default=None, kind: type | None = None):
    """The JSON in path; default if it isn't there. A file that can't be read
    or isn't `kind` raises ValueError (callers decide whether to set it aside)."""
    try:
        raw = Path(path).read_text(encoding="utf-8")
    except FileNotFoundError:
        return default
    value = json.loads(raw)
    if kind is not None and not isinstance(value, kind):
        raise ValueError(f"{Path(path).name} isn't a JSON {kind.__name__}.")
    return value


def keep_aside(path, label: str = "broken") -> Path | None:
    """A copy of a damaged path under a name of its own beside it
    ("events.broken-20261026-101500.json", "-2" if that's taken), the
    original left where it is. None if there's nothing there."""
    path = Path(path)
    if not path.exists():
        return None
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    n = 1
    while True:
        name = f"{path.stem}.{label}-{stamp}{'' if n == 1 else f'-{n}'}{path.suffix}"
        kept = path.with_name(name)
        n += 1
        try:
            with open(kept, "xb") as out:
                out.write(path.read_bytes())
                out.flush()
                os.fsync(out.fileno())
            return kept
        except FileExistsError:
            continue


def copy_backup(path, backup) -> bool:
    """backup becomes a copy of path (with its times), if path is there."""
    path = Path(path)
    if not path.exists():
        return False
    Path(backup).parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, backup)
    return True


@contextlib.contextmanager
def locked(lockfile):
    """Holds an exclusive lock on lockfile (made if need be) for the block:
    two helpers writing the same store take turns."""
    lockfile = Path(lockfile)
    lockfile.parent.mkdir(parents=True, exist_ok=True)
    with open(lockfile, "a") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(handle, fcntl.LOCK_UN)
