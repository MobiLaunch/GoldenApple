#!/usr/bin/env python3
"""gg-idle: hypridle's settings from Settings → Lock Screen.

desktop.json's "lockScreen" (all optional):
  { "displayOff": 600,     seconds idle before the display turns off; 0 = never
    "requireAfter": 0,     seconds after that before the password is asked; -1 = never
    "dim": true }          dim the display halfway to turning it off

Writes ~/.config/hypr/hypridle.conf and restarts hypridle if it's running.
Going to sleep always locks, as on the Mac.

  gg-idle            write it and restart hypridle
  gg-idle --print    print it (what the shipped hypridle.conf is, by default)
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

DEFAULTS = {"displayOff": 600, "requireAfter": 0, "dim": True}


def settings() -> dict:
    config = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
    try:
        lock = json.loads((config / "golden-gate/desktop.json").read_text()).get("lockScreen") or {}
    except (OSError, ValueError, AttributeError):
        lock = {}
    out = dict(DEFAULTS)
    for key in DEFAULTS:
        if key in lock and isinstance(lock[key], type(DEFAULTS[key])):
            out[key] = lock[key]
    return out


def conf(s: dict) -> str:
    off, require = max(0, int(s["displayOff"])), int(s["requireAfter"])
    lines = [
        "# Written by CitronOS Settings → Lock Screen (gg-idle); changes here are replaced.",
        "general {",
        "    lock_cmd = qs -c golden-gate ipc call lock lock",
        "    before_sleep_cmd = loginctl lock-session",
        "    after_sleep_cmd = hyprctl dispatch dpms on",
        "}",
    ]

    def listener(timeout: int, on: str, resume: str = "") -> None:
        lines.extend(["listener {", f"    timeout = {timeout}", f"    on-timeout = {on}"]
                     + ([f"    on-resume = {resume}"] if resume else []) + ["}"])

    if off:
        if s["dim"] and off >= 20:
            listener(off // 2, "brightnessctl -s set 20%", "brightnessctl -r")
        listener(off, "hyprctl dispatch dpms off", "hyprctl dispatch dpms on")
        if require >= 0:
            listener(off + require, "loginctl lock-session")
    return "\n".join(lines) + "\n"


def main() -> int:
    text = conf(settings())
    if "--print" in sys.argv[1:]:
        sys.stdout.write(text)
        return 0
    path = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "hypr/hypridle.conf"
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(text)
    os.replace(tmp, path)
    # hypridle reads its settings once: start it again with the new ones.
    if shutil.which("hypridle") and subprocess.run(["pgrep", "-x", "-u", str(os.getuid()), "hypridle"],
                                                   capture_output=True).returncode == 0:
        subprocess.run(["pkill", "-x", "-u", str(os.getuid()), "hypridle"], capture_output=True)
        subprocess.Popen(["hypridle"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
