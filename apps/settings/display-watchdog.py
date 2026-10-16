#!/usr/bin/env python3
"""Puts the displays back unless a change is kept, whatever happens to
Settings meanwhile (closed, the pane left, a crash).

    display-watchdog.py arm TOKEN SECONDS RULE...   started detached by Displays
    display-watchdog.py keep TOKEN                   the change was kept (and saved)
    display-watchdog.py revert TOKEN                 put it back now

arm writes TOKEN (in $XDG_RUNTIME_DIR), waits SECONDS, and if TOKEN is still
there applies the RULEs (the monitor rules from before the change) with
hyprctl and removes it. keep removes TOKEN, so nothing happens; revert
applies the rules at once. Each prints {"ok": …}."""
from __future__ import annotations

import json
import os
import pathlib
import subprocess
import sys
import time


def token_path(name: str) -> pathlib.Path:
    base = pathlib.Path(os.environ.get("XDG_RUNTIME_DIR") or "/tmp")
    clean = "".join(c for c in name if c.isalnum() or c in "-_")
    return base / f"gg-display-trial-{clean}"


def apply(rules: list[str]) -> bool:
    if not rules:
        return True
    try:
        p = subprocess.run(["hyprctl", "--batch", " ; ".join("keyword monitor " + r for r in rules)],
                           capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.SubprocessError):
        return False
    return p.returncode == 0 and "invalid" not in p.stdout.lower() and "error" not in p.stdout.lower()


def say(ok: bool, **kw) -> int:
    print(json.dumps({"ok": ok, **kw}), flush=True)
    return 0 if ok else 1


def main(argv: list[str]) -> int:
    if len(argv) < 3 or argv[1] not in ("arm", "keep", "revert"):
        print(__doc__, file=sys.stderr)
        return 2
    token = token_path(argv[2])
    if argv[1] == "arm":
        seconds, rules = float(argv[3]), argv[4:]
        token.write_text(json.dumps(rules))
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            if not token.exists():
                return say(True, kept=True)
            time.sleep(0.2)
        if not token.exists():
            return say(True, kept=True)
        token.unlink(missing_ok=True)
        return say(apply(rules), reverted=True)
    if argv[1] == "keep":
        token.unlink(missing_ok=True)
        return say(True)
    try:
        rules = json.loads(token.read_text())
    except (OSError, ValueError):
        return say(True, reverted=False)            # nothing pending
    token.unlink(missing_ok=True)
    return say(apply(rules), reverted=True)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
