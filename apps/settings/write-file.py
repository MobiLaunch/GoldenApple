#!/usr/bin/env python3
"""Replace one preference file, atomically, for Settings.

    write-file.py PATH < CONTENT

The new content goes to a temporary file beside PATH, is flushed to disk
and renamed over it, under a lock (PATH's directory, .NAME.lock) so two
writers take turns. Either the whole new file is there, or the old one is
untouched; the exit status says which (with the reason on stderr), so
Settings can tell you a change wasn't saved."""
from __future__ import annotations

import fcntl
import os
import pathlib
import sys
import tempfile


def write(target: pathlib.Path, data: bytes) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    with open(target.parent / f".{target.name}.lock", "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        fd, tmp = tempfile.mkstemp(prefix=f".{target.name}.", suffix=".tmp", dir=target.parent)
        try:
            with os.fdopen(fd, "wb") as f:
                f.write(data)
                f.flush()
                os.fsync(f.fileno())
            try:
                os.chmod(tmp, target.stat().st_mode & 0o777)
            except FileNotFoundError:
                os.chmod(tmp, 0o644)
            os.replace(tmp, target)
        finally:
            try:
                os.unlink(tmp)
            except FileNotFoundError:
                pass


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: write-file.py PATH < CONTENT", file=sys.stderr)
        return 2
    try:
        write(pathlib.Path(argv[1]), sys.stdin.buffer.read())
    except OSError as exc:
        print(exc.strerror or str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
