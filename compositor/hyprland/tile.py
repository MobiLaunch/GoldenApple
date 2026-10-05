#!/usr/bin/env python3
"""gg-tile: move and resize the front window, as macOS Sequoia's Window ›
Move & Resize does. Every CitronOS window floats, so tiling is geometry:
the screen's usable area (less the menu bar and the Dock, which Hyprland
reports as reserved), with a gap around and between tiles.

    gg-tile left|right|top|bottom|top-left|top-right|bottom-left|bottom-right
    gg-tile fill|center|restore [ADDRESS]

restore puts the window back where it was before it was first tiled. Bound to
⌃⌥ + arrows/U I J K/Return/C/Backspace in hyprland.conf, and in the menu
bar's Window menu and the green button's menu.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys

GAP = 8
LAYOUTS = {
    # (x, y, w, h) as fractions of the usable area
    "left": (0, 0, .5, 1), "right": (.5, 0, .5, 1), "top": (0, 0, 1, .5), "bottom": (0, .5, 1, .5),
    "top-left": (0, 0, .5, .5), "top-right": (.5, 0, .5, .5),
    "bottom-left": (0, .5, .5, .5), "bottom-right": (.5, .5, .5, .5),
    "fill": (0, 0, 1, 1),
}


def hyprctl(*args: str) -> str:
    return subprocess.run(["hyprctl", *args], capture_output=True, text=True).stdout


def state_file() -> Path:
    return Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "gg-tile.json"


def area(monitor: dict) -> tuple[float, float, float, float]:
    """The monitor's usable area in layout coordinates, inside the gap."""
    scale = monitor.get("scale") or 1
    w, h = monitor["width"] / scale, monitor["height"] / scale
    if monitor.get("transform", 0) % 2:
        w, h = h, w
    left, top, right, bottom = (monitor.get("reserved") or [0, 0, 0, 0])[:4]
    return (monitor["x"] + left + GAP, monitor["y"] + top + GAP,
            w - left - right - 2 * GAP, h - top - bottom - 2 * GAP)


def rect(layout: str, window: dict, usable: tuple) -> tuple[int, int, int, int]:
    ax, ay, aw, ah = usable
    if layout == "center":
        w, h = min(window["size"][0], aw), min(window["size"][1], ah)
        return round(ax + (aw - w) / 2), round(ay + (ah - h) / 2), round(w), round(h)
    fx, fy, fw, fh = LAYOUTS[layout]
    # Half a gap between neighbouring tiles on each side of the split.
    x = ax + fx * aw + (GAP / 2 if fx else 0)
    y = ay + fy * ah + (GAP / 2 if fy else 0)
    w = fw * aw - (GAP / 2 if fw < 1 else 0)
    h = fh * ah - (GAP / 2 if fh < 1 else 0)
    return round(x), round(y), round(w), round(h)


def main(argv: list[str]) -> int:
    if not argv or argv[0] not in (*LAYOUTS, "center", "restore"):
        print(__doc__.strip(), file=sys.stderr)
        return 2
    layout = argv[0]
    try:
        window = json.loads(hyprctl("-j", "activewindow") or "{}")
        if len(argv) > 1:
            window = next((c for c in json.loads(hyprctl("-j", "clients") or "[]") if c.get("address") == argv[1]), window)
        monitors = json.loads(hyprctl("-j", "monitors") or "[]")
    except ValueError:
        return 1
    if not window.get("address") or window.get("fullscreen"):
        return 1
    monitor = next((m for m in monitors if m.get("id") == window.get("monitor")), monitors[0] if monitors else None)
    if not monitor:
        return 1
    address = window["address"]
    saved = {}
    try:
        saved = json.loads(state_file().read_text())
    except (OSError, ValueError):
        pass
    if layout == "restore":
        if address not in saved:
            return 0
        x, y, w, h = saved.pop(address)
    else:
        x, y, w, h = rect(layout, window, area(monitor))
        # Remember where it was before its first tile, for Return to Previous Size.
        saved.setdefault(address, [*window["at"], *window["size"]])
    try:
        state_file().write_text(json.dumps(saved))
    except OSError:
        pass
    target = f"address:{address}"
    commands = [] if window.get("floating") else [f"dispatch setfloating {target}"]
    commands += [f"dispatch resizewindowpixel exact {w} {h},{target}", f"dispatch movewindowpixel exact {x} {y},{target}"]
    hyprctl("--batch", " ; ".join(commands))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
