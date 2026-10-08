#!/usr/bin/env python3
"""CitronOS Notes: Recently Deleted.

    trash.py delete  ROOT PATH    move a note into ROOT/Recently Deleted
    trash.py recover ROOT PATH    put a deleted note back where it was
    trash.py erase   ROOT PATH    delete a note in Recently Deleted for good
    trash.py rename  ROOT PATH NAME   give a note a new file name (its title)

A deleted note keeps its file name unless one is already there, then it's
"Title 2.md" and so on: nothing in Recently Deleted is ever replaced. Where it
came from is kept in ROOT/Recently Deleted/.origins.json, so it can be put
back; if a note of that name is there again, the recovered one is "Title 2.md".
Rename never replaces a note either: a taken name becomes "Title 2.md".

Every command runs under one lock (ROOT/.notes.lock), so two windows
deleting, recovering or renaming at once keep every note and every
origin. A note's origin is recorded before its old file is removed: if
that record can't be written, the move is undone and the note stays put.
Prints {"ok": true, "path": …} or {"ok": false, "error": …}."""
from __future__ import annotations

import fcntl
import json
import os
import pathlib
import sys
import tempfile

TRASH = "Recently Deleted"


def say(ok: bool, **payload: object) -> int:
    print(json.dumps({"ok": ok, **payload}))
    return 0 if ok else 1


def origins_file(root: pathlib.Path) -> pathlib.Path:
    return root / TRASH / ".origins.json"


def load_origins(root: pathlib.Path) -> dict:
    try:
        data = json.loads(origins_file(root).read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except FileNotFoundError:
        return {}
    except (OSError, ValueError):
        # Unreadable: keep it for whoever looks, start a new one.
        bad = origins_file(root)
        try:
            bad.rename(bad.with_name(".origins.broken.json"))
        except OSError:
            pass
        return {}


def save_origins(root: pathlib.Path, origins: dict) -> None:
    target = origins_file(root)
    fd, tmp = tempfile.mkstemp(dir=target.parent, prefix=".origins.", suffix=".tmp")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(origins, f, ensure_ascii=False, indent=1)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, target)


def claim(src: pathlib.Path, folder: pathlib.Path, name: str = "") -> pathlib.Path:
    """A copy of src in folder as name (its own by default), or "name 2.md"…
    if that's taken. A hard link claims the name atomically (it fails if
    anything is there); without hard links, an exclusive copy does the same.
    src is left in place: finish with os.unlink(src), or undo with
    os.unlink(the result)."""
    first = pathlib.Path(name or src.name)
    n = 1
    while True:
        dst = folder / (first.name if n == 1 else f"{first.stem} {n}{first.suffix}")
        n += 1
        try:
            os.link(src, dst, follow_symlinks=False)
            return dst
        except FileExistsError:
            continue
        except OSError:
            # No hard links here (another disk, or a filesystem without them).
            try:
                with open(dst, "xb") as out, open(src, "rb") as inp:
                    out.write(inp.read())
                    out.flush()
                    os.fsync(out.fileno())
            except FileExistsError:
                continue
            try:
                os.utime(dst, ns=(src.stat().st_atime_ns, src.stat().st_mtime_ns))
            except OSError:
                pass
            return dst


def move_without_replacing(src: pathlib.Path, folder: pathlib.Path, name: str = "") -> pathlib.Path:
    dst = claim(src, folder, name)
    os.unlink(src)
    return dst


class locked:
    def __init__(self, root: pathlib.Path):
        self.path = root / ".notes.lock"

    def __enter__(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.f = open(self.path, "a")
        fcntl.flock(self.f, fcntl.LOCK_EX)
        return self

    def __exit__(self, *exc):
        fcntl.flock(self.f, fcntl.LOCK_UN)
        self.f.close()


def inside(path: pathlib.Path, root: pathlib.Path) -> bool:
    return root == path or root in path.parents


def main(argv: list[str]) -> int:
    commands = ("delete", "recover", "erase", "rename")
    if len(argv) not in (4, 5) or argv[1] not in commands or (argv[1] == "rename") != (len(argv) == 5):
        return say(False, error=__doc__.strip().splitlines()[2])
    command, root, path = argv[1], pathlib.Path(argv[2]).absolute(), pathlib.Path(argv[3]).absolute()
    trash = root / TRASH
    if not inside(path, root) or path.suffix != ".md":
        return say(False, error="That isn't a note.")
    try:
        with locked(root):
            if not os.path.lexists(path):
                return say(False, error=f"“{path.stem}” is no longer there.")
            if command == "rename":
                name = argv[4].replace("/", "-").strip()
                if not name.endswith(".md") or name in (".md", "..md"):
                    return say(False, error="That isn't a note's name.")
                if name == path.name:
                    return say(True, path=str(path))
                return say(True, path=str(move_without_replacing(path, path.parent, name)))
            if command == "delete":
                if path.parent == trash:
                    return say(False, error="That note is already in Recently Deleted.")
                trash.mkdir(parents=True, exist_ok=True)
                origins = load_origins(root)
                dst = claim(path, trash)
                origins[dst.name] = str(path)
                try:
                    save_origins(root, origins)
                except OSError:
                    os.unlink(dst)                    # where it came from couldn't be kept: undo
                    raise
                os.unlink(path)
                return say(True, path=str(dst))
            if path.parent != trash:
                return say(False, error="That note isn't in Recently Deleted.")
            origins = load_origins(root)
            if command == "erase":
                path.unlink()
                dst = path
            else:
                was = pathlib.Path(origins.get(path.name) or root / "Notes" / path.name)
                folder = was.parent if inside(was.parent, root) and was.parent != trash else root / "Notes"
                folder.mkdir(parents=True, exist_ok=True)
                # Back under the name it had, or "Title 2.md" if that's taken now.
                dst = move_without_replacing(path, folder, was.name if was.suffix == ".md" else "")
            origins.pop(path.name, None)
            save_origins(root, origins)
            return say(True, path=str(dst))
    except OSError as exc:
        return say(False, error=exc.strerror or str(exc))


if __name__ == "__main__":
    sys.exit(main(sys.argv))
