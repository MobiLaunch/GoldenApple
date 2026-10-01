#!/usr/bin/env python3
"""Golden Gate Software Update backend.

check: unprivileged refresh/check via checkupdates.
apply: run as root (sudo/pkexec); streams JSON progress for Settings.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime


def emit(event: str, **payload: object) -> None:
    print(json.dumps({"event": event, **payload}, separators=(",", ":")), flush=True)


def check() -> int:
    emit("checking", progress=0.08, message="Refreshing package information…")
    tool = shutil.which("checkupdates")
    if not tool:
        # A stale local query is still more useful than a dead Settings pane.
        proc = subprocess.run(["pacman", "-Qu"], text=True, capture_output=True)
        lines = [line for line in proc.stdout.splitlines() if line.strip()]
        emit("result", count=len(lines), packages=lines[:20], stale=True,
             message="Install pacman-contrib to refresh update metadata safely.")
        return 0

    try:
        proc = subprocess.run([tool], text=True, capture_output=True, timeout=60)
    except subprocess.TimeoutExpired:
        emit("error", message="The update check timed out. Check your internet connection and try again.")
        return 124
    except OSError as exc:
        emit("error", message=str(exc))
        return 127
    # checkupdates returns 2 when there are no available updates.
    if proc.returncode not in (0, 2):
        message = (proc.stderr or proc.stdout or "Update check failed.").strip().splitlines()[-1]
        emit("error", message=message)
        return proc.returncode or 1

    packages = [line.strip() for line in proc.stdout.splitlines() if line.strip()]
    emit("result", count=len(packages), packages=packages[:30], stale=False)
    return 0


def apply() -> int:
    if os.geteuid() != 0:
        emit("error", message="Software Update needs administrator authorization.")
        return 77

    emit("progress", progress=0.03, message="Preparing update…", remaining=-1)
    cmd = ["pacman", "-Syu", "--noconfirm", "--noprogressbar"]
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        env={**os.environ, "LC_ALL": "C"},
    )

    transaction = re.compile(
        r"\(\s*(\d+)\/(\d+)\)\s+(?:upgrading|installing|reinstalling|removing)\s+(.+)$",
        re.IGNORECASE,
    )
    last_message = ""
    assert proc.stdout is not None
    for raw in proc.stdout:
        line = raw.strip()
        if not line:
            continue

        match = transaction.search(line)
        if match:
            current, total = int(match.group(1)), int(match.group(2))
            package = match.group(3).strip()
            remaining = max(0, total - current)
            progress = 0.28 + 0.67 * (current / max(1, total))
            emit(
                "progress",
                progress=progress,
                current=current,
                total=total,
                remaining=remaining,
                message=f"Installing {package}",
            )
            continue

        lower = line.lower()
        if "synchronizing package databases" in lower:
            last_message = "Refreshing software catalog…"
            emit("progress", progress=0.08, message=last_message, remaining=-1)
        elif "resolving dependencies" in lower or "looking for conflicting packages" in lower:
            last_message = "Resolving dependencies…"
            emit("progress", progress=0.18, message=last_message, remaining=-1)
        elif "retrieving packages" in lower:
            last_message = "Downloading updates…"
            emit("progress", progress=0.24, message=last_message, remaining=-1)
        elif "running post-transaction hooks" in lower:
            last_message = "Finishing installation…"
            emit("progress", progress=0.97, message=last_message, remaining=0)
        elif line.startswith("error:"):
            last_message = line

    code = proc.wait()
    if code == 0:
        emit("done", progress=1.0, message="Golden Gate is up to date.", completed=datetime.now().isoformat())
        return 0

    emit("error", message=last_message or f"pacman exited with status {code}.")
    return code


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in {"check", "apply"}:
        print("usage: update-helper.py check|apply", file=sys.stderr)
        return 2
    return check() if sys.argv[1] == "check" else apply()


if __name__ == "__main__":
    raise SystemExit(main())
