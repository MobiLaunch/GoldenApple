"""Append-only logs, one JSON object per line (notification history,
activity logs). Each append is one write under a lock, synced; reading
skips a last line torn by a crash, and anything else unreadable."""
from __future__ import annotations

import fcntl
import json
import os
from pathlib import Path

from .files import atomic_write

MAX_LINE = 1 << 20


def append(path, record: dict) -> None:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    line = json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n"
    if len(line) > MAX_LINE:
        raise ValueError("The record is too large for the log.")
    fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        # A torn last line (a crash mid-write) gets its own line ended first,
        # so this record isn't glued onto it.
        size = os.fstat(fd).st_size
        if size:
            with open(path, "rb") as check:
                check.seek(size - 1)
                if check.read(1) != b"\n":
                    os.write(fd, b"\n")
        os.write(fd, line.encode("utf-8"))
        os.fsync(fd)
    finally:
        os.close(fd)


def read(path, limit: int | None = None) -> list[dict]:
    """The records, oldest first (the last `limit` if given)."""
    out = []
    try:
        with open(path, "rb") as stream:
            for raw in stream:
                if not raw.endswith(b"\n") or len(raw) > MAX_LINE:
                    continue
                try:
                    value = json.loads(raw)
                except ValueError:
                    continue
                if isinstance(value, dict):
                    out.append(value)
    except FileNotFoundError:
        return []
    return out[-limit:] if limit else out


def rewrite(path, records: list[dict]) -> None:
    """The log becomes exactly these records, all at once (pruning)."""
    text = "".join(json.dumps(r, ensure_ascii=False, separators=(",", ":")) + "\n" for r in records)
    atomic_write(path, text)
