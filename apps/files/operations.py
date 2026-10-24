#!/usr/bin/env python3
"""Files transfers: private staging, no replacement, progress and cancellation.

The first stdin line is a request. Later lines answer name conflicts or cancel.
Each stdout line is an event. Completed items survive cancellation; an unfinished
copy is removed from its private staging directory and its source stays intact.
"""
from __future__ import annotations

import errno
import json
import os
from pathlib import Path
import queue
import shutil
import signal
import stat
import sys
import tempfile
import threading
import time

from helper import rename_noreplace, unique


class Cancelled(Exception):
    pass


def identity(path: Path) -> list[int]:
    s = path.lstat()
    return [s.st_dev, s.st_ino]


def snapshot(path: Path) -> tuple[int, ...]:
    s = path.lstat()
    return s.st_dev, s.st_ino, s.st_mode, s.st_size, s.st_mtime_ns, s.st_ctime_ns


class Transfer:
    def __init__(self, request, emit, controls=None):
        self.request = request
        self.emit = emit
        self.controls = controls or queue.Queue()
        self.cancelled = threading.Event()
        self.policy = request.get("conflicts", "ask")
        if self.policy not in ("ask", "keep-both", "skip"):
            raise ValueError("Choose Keep Both or Skip for name conflicts.")
        self.completed = []
        self.skipped = []
        self.errors = []
        self.bytes = 0
        self.total_bytes = 0
        self.last_progress = 0
        self.fingerprints = {}

    def check(self):
        if self.cancelled.is_set():
            raise Cancelled()

    def progress(self, name="", force=False):
        now = time.monotonic()
        if force or now - self.last_progress > .1:
            self.last_progress = now
            self.emit(dict(event="progress", name=name, bytes=self.bytes,
                           totalBytes=self.total_bytes, completed=len(self.completed),
                           skipped=len(self.skipped), total=self.total))

    def conflict(self, src, target):
        policy = self.policy
        if policy == "ask":
            self.emit(dict(event="conflict", name=target.name, source=str(src), destination=str(target)))
            while True:
                self.check()
                try:
                    answer = self.controls.get(timeout=.1)
                except queue.Empty:
                    continue
                policy = answer.get("answer")
                if policy == "eof":
                    raise ValueError("The name conflict needs a choice. Try the transfer again.")
                if policy not in ("keep-both", "skip"):
                    continue
                if answer.get("all"):
                    self.policy = policy
                break
        return unique(target) if policy == "keep-both" else None

    def target(self, src, dest):
        target = dest / src.name
        return self.conflict(src, target) if os.path.lexists(target) else target

    def scan(self, src):
        self.check()
        s = src.lstat()
        self.fingerprints[str(src)] = snapshot(src)
        if stat.S_ISREG(s.st_mode):
            self.total_bytes += s.st_size
        elif stat.S_ISDIR(s.st_mode):
            for child in src.iterdir():
                self.scan(child)
        elif not stat.S_ISLNK(s.st_mode):
            raise ValueError(f"“{src.name}” is a special device or socket and can't be copied.")

    def copy(self, src, dst):
        self.check()
        before = self.fingerprints.get(str(src))
        if before is None:
            raise ValueError(f"“{src.name}” appeared while copying. Try again.")
        if snapshot(src) != before:
            raise ValueError(f"“{src.name}” changed while preparing. Try again.")
        mode = before[2]
        if stat.S_ISLNK(mode):
            dst.symlink_to(os.readlink(src))
        elif stat.S_ISDIR(mode):
            dst.mkdir()
            for child in src.iterdir():
                self.copy(child, dst / child.name)
        elif stat.S_ISREG(mode):
            fd = os.open(src, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
            with os.fdopen(fd, "rb") as inp, dst.open("xb") as out:
                s = os.fstat(inp.fileno())
                if (s.st_dev, s.st_ino, s.st_mode, s.st_size, s.st_mtime_ns, s.st_ctime_ns) != before:
                    raise ValueError(f"“{src.name}” changed before it could be copied.")
                while True:
                    self.check()
                    chunk = inp.read(1024 * 1024)
                    if not chunk:
                        break
                    out.write(chunk)
                    self.bytes += len(chunk)
                    self.progress(src.name)
                out.flush()
                os.fsync(out.fileno())
        else:
            raise ValueError(f"“{src.name}” can't be copied.")
        if snapshot(src) != before:
            raise ValueError(f"“{src.name}” changed while copying. The original was kept.")
        shutil.copystat(src, dst, follow_symlinks=False)

    def verify_source(self, src):
        self.check()
        if snapshot(src) != self.fingerprints.get(str(src)):
            raise ValueError(f"“{src.name}” changed while copying. Both copies were kept.")
        if src.is_dir() and not src.is_symlink():
            for child in src.iterdir():
                self.verify_source(child)

    def publish(self, stage, src, target):
        while target is not None:
            self.check()
            try:
                rename_noreplace(stage, target)
                return target
            except FileExistsError:
                target = self.conflict(src, target)
        return None

    def item(self, src, dest, move):
        target = self.target(src, dest)
        if target is None:
            self.skipped.append(str(src)); return
        if move:
            try:
                target = self.publish(src, src, target)
                if target is None:
                    self.skipped.append(str(src)); return
                self.completed.append(dict(source=str(src), path=str(target), action="move", identity=identity(target)))
                return
            except OSError as exc:
                if exc.errno != errno.EXDEV:
                    raise
        with tempfile.TemporaryDirectory(prefix=".golden-gate-transfer-", dir=dest) as temp:
            stage = Path(temp) / src.name
            self.copy(src, stage)
            target = self.publish(stage, src, target)
            if target is None:
                self.skipped.append(str(src)); return
            record = dict(source=str(src), path=str(target), action="copy", identity=identity(target))
            self.completed.append(record)
            # Never delete the source of a cancelled or changed cross-disk
            # move. A complete destination remains available in the summary.
            if move:
                self.verify_source(src)
                if src.is_dir() and not src.is_symlink():
                    shutil.rmtree(src)
                else:
                    src.unlink()
                record["action"] = "move"

    def run(self):
        mode = self.request.get("mode", "copy")
        if mode not in ("copy", "move", "auto", "duplicate"):
            raise ValueError("That transfer action isn't supported.")
        raws = self.request.get("paths")
        if not isinstance(raws, list) or not raws or any(not isinstance(p, str) or not p for p in raws):
            raise ValueError("Select at least one file or folder.")
        if any(not os.path.isabs(p) for p in raws):
            raise ValueError("Files needs absolute paths for this transfer.")
        paths = list(dict.fromkeys(Path(p).expanduser().absolute() for p in raws))
        # A selected folder already carries its selected children.
        paths = [p for p in paths if not any(other != p and other in p.parents and other.is_dir()
                                           and not other.is_symlink() for other in paths)]
        self.total = len(paths)
        if mode == "duplicate":
            self.policy = "keep-both"
        destination = self.request.get("destination")
        if mode != "duplicate" and (not isinstance(destination, str) or not os.path.isabs(destination)):
            raise ValueError("Choose a destination folder.")
        dest = None if mode == "duplicate" else Path(destination).resolve()
        if dest is not None and not dest.is_dir():
            raise ValueError("The destination folder is no longer available.")
        self.emit(dict(event="start", total=self.total))
        try:
            self.emit(dict(event="preparing"))
            usable = []
            for src in paths:
                self.check()
                try:
                    target_dir = src.parent if mode == "duplicate" else dest
                    if src.is_dir() and not src.is_symlink() and (src.resolve() == target_dir or src.resolve() in target_dir.parents):
                        raise ValueError(f"“{src.name}” can't be transferred into itself.")
                    if mode in ("move", "auto") and src.parent.resolve() == target_dir:
                        self.skipped.append(str(src)); continue
                    self.scan(src)
                    usable.append((src, target_dir))
                except (OSError, ValueError) as exc:
                    self.errors.append(dict(path=str(src), error=str(exc)))
            self.progress(force=True)
            for src, target_dir in usable:
                self.check()
                try:
                    self.emit(dict(event="item", name=src.name))
                    move = mode == "move" or (mode == "auto" and src.lstat().st_dev == target_dir.stat().st_dev)
                    self.item(src, target_dir, move)
                except (OSError, ValueError) as exc:
                    self.errors.append(dict(path=str(src), error=str(exc)))
                self.progress(src.name, force=True)
        except Cancelled:
            self.cancelled.set()
        r = dict(event="finished", ok=not self.errors, cancelled=self.cancelled.is_set(),
                 completed=self.completed, skipped=self.skipped, errors=self.errors,
                 total=self.total, bytes=self.bytes, totalBytes=self.total_bytes,
                 destination=str(dest) if dest else "")
        self.emit(r)
        return r


def main():
    def emit(event):
        print(json.dumps(event, separators=(",", ":")), flush=True)
    try:
        request = json.loads(sys.stdin.readline())
        if not isinstance(request, dict):
            raise ValueError("The transfer request wasn't valid.")
        transfer = Transfer(request, emit)
        def controls():
            for line in sys.stdin:
                try:
                    answer = json.loads(line)
                    if answer.get("cancel"):
                        transfer.cancelled.set()
                    else:
                        transfer.controls.put(answer)
                except (ValueError, AttributeError):
                    pass
            transfer.controls.put({"answer": "eof"})
        threading.Thread(target=controls, daemon=True).start()
        signal.signal(signal.SIGTERM, lambda *_: transfer.cancelled.set())
        signal.signal(signal.SIGINT, lambda *_: transfer.cancelled.set())
        r = transfer.run()
        return 0 if r["ok"] else 1
    except (OSError, ValueError, TypeError) as exc:
        emit(dict(event="finished", ok=False, cancelled=False, completed=[], skipped=[],
                  errors=[dict(error=str(exc))]))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
