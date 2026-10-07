#!/usr/bin/env python3
"""CitronOS Notes: Recently Deleted.

    trash.py delete  ROOT PATH    move a note into ROOT/Recently Deleted
    trash.py recover ROOT PATH    put a deleted note back where it was
    trash.py erase   ROOT PATH    delete a note in Recently Deleted for good

A deleted note keeps its file name unless one is already there, then it's
"Title 2.md" and so on: nothing in Recently Deleted is ever replaced. Where it
came from is kept in ROOT/Recently Deleted/.origins.json, so it can be put
back; if a note of that name is there again, the recovered one is "Title 2.md".
Prints {"ok": true, "path": …} or {"ok": false, "error": …}."""
from __future__ import annotations

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


def move_without_replacing(src: pathlib.Path, folder: pathlib.Path, name: str = "") -> pathlib.Path:
    """src into folder as name (its own by default), or "name 2.md"… if that's taken.
    A hard link claims the name atomically (it fails if anything is there),
    then the original goes; across disks, an exclusive copy does the same."""
    first = pathlib.Path(name or src.name)
    n = 1
    while True:
        dst = folder / (first.name if n == 1 else f"{first.stem} {n}{first.suffix}")
        n += 1
        try:
            os.link(src, dst, follow_symlinks=False)
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
        os.unlink(src)
        return dst


def inside(path: pathlib.Path, root: pathlib.Path) -> bool:
    return root == path or root in path.parents


def main(argv: list[str]) -> int:
    if len(argv) != 4 or argv[1] not in ("delete", "recover", "erase"):
        return say(False, error=__doc__.strip().splitlines()[2])
    command, root, path = argv[1], pathlib.Path(argv[2]).absolute(), pathlib.Path(argv[3]).absolute()
    trash = root / TRASH
    if not inside(path, root) or path.suffix != ".md":
        return say(False, error="That isn't a note.")
    if not os.path.lexists(path):
        return say(False, error=f"“{path.stem}” is no longer there.")
    try:
        if command == "delete":
            if path.parent == trash:
                return say(False, error="That note is already in Recently Deleted.")
            trash.mkdir(parents=True, exist_ok=True)
            origins = load_origins(root)
            dst = move_without_replacing(path, trash)
            origins[dst.name] = str(path)
            save_origins(root, origins)
            return say(True, path=str(dst))
        if path.parent != trash:
            return say(False, error="That note isn't in Recently Deleted.")
        origins = load_origins(root)
        if command == "erase":
            path.unlink()
        else:
            was = pathlib.Path(origins.get(path.name) or root / "Notes" / path.name)
            folder = was.parent if inside(was.parent, root) and was.parent != trash else root / "Notes"
            folder.mkdir(parents=True, exist_ok=True)
            # Back under the name it had, or "Title 2.md" if that's taken now.
            dst = move_without_replacing(path, folder, was.name if was.suffix == ".md" else "")
        origins.pop(path.name, None)
        save_origins(root, origins)
        return say(True, path=str(dst) if command == "recover" else str(path))
    except OSError as exc:
        return say(False, error=exc.strerror or str(exc))


if __name__ == "__main__":
    sys.exit(main(sys.argv))
