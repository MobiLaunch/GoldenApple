#!/usr/bin/env python3
"""Which apps are being given your location, for the menu bar's arrow.

Prints one JSON list of app names whenever it changes, e.g. ["Weather"]:
- CitronOS's location helper leaves a file under $XDG_RUNTIME_DIR/citron-location
  while it locates and for a few seconds after ({"app", "pid", "until"}); a
  file left by a helper that is gone is removed.
- GeoClue says whether any other app is being given a location ("An app")."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import time

RUN = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}") / "citron-location"


def helper_users() -> set[str]:
    use = set()
    for f in RUN.glob("*.json") if RUN.is_dir() else []:
        try:
            data = json.loads(f.read_text())
            if time.time() > float(data.get("until") or 0):
                os.kill(int(data["pid"]), 0)          # still locating, or gone (raises)
            use.add(str(data.get("app") or "An app"))
        except (OSError, ValueError, KeyError, TypeError):
            try:
                f.unlink()
            except OSError:
                pass
    return use


def geoclue_in_use() -> bool:
    try:
        out = subprocess.run(["busctl", "--system", "get-property", "org.freedesktop.GeoClue2",
                              "/org/freedesktop/GeoClue2/Manager", "org.freedesktop.GeoClue2.Manager", "InUse"],
                             capture_output=True, text=True, timeout=2).stdout
        return out.strip() == "b true"
    except (OSError, subprocess.SubprocessError):
        return False


def main() -> int:
    last, tick, in_use = None, 0, False
    geoclue = Path("/usr/share/dbus-1/system-services/org.freedesktop.GeoClue2.service").exists()
    while True:
        use = helper_users()
        if geoclue and tick % 3 == 0:
            in_use = geoclue_in_use()
        if geoclue and in_use:
            use.add("An app")
        now = sorted(use)
        if now != last:
            print(json.dumps(now), flush=True)
            last = now
        tick += 1
        time.sleep(2)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (KeyboardInterrupt, BrokenPipeError):
        sys.exit(0)
