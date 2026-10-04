#!/usr/bin/env python3
"""gg-tile (compositor/hyprland/tile.py): Window › Move & Resize.

A fake hyprctl answers with a 1440×900 monitor at scale 1, the menu bar (30)
and the Dock (78) reserved, and records what gg-tile dispatches. Each layout
lands inside the usable area with an 8 px gap, neighbouring halves meet with
one gap between them, Return to Previous Size puts the window back, and a
tiled window is made floating first. The ⌃⌥ keys, the menu bar's Window menu
and the green button's menu all call it, and it's installed as gg-tile."""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TILE = ROOT / "compositor/hyprland/tile.py"

FAKE = r'''#!/usr/bin/env python3
import json, os, sys
state = json.load(open(os.environ["FAKE_STATE"]))
args = sys.argv[1:]
if args[:2] == ["-j", "activewindow"]:
    print(json.dumps(state["window"]))
elif args[:2] == ["-j", "clients"]:
    print(json.dumps(state.get("clients", [state["window"]])))
elif args[:2] == ["-j", "monitors"]:
    print(json.dumps(state["monitors"]))
elif args[:1] == ["--batch"]:
    with open(os.environ["FAKE_LOG"], "a") as f:
        f.write(args[1] + "\n")
'''

MONITOR = {"id": 0, "name": "eDP-1", "x": 0, "y": 0, "width": 1440, "height": 900, "scale": 1,
           "transform": 0, "reserved": [0, 30, 0, 78]}
failures: list[str] = []


def check(cond: bool, what: str) -> None:
    if not cond:
        failures.append(what)


with tempfile.TemporaryDirectory() as tmp:
    tmp = Path(tmp)
    (tmp / "bin").mkdir()
    fake = tmp / "bin/hyprctl"
    fake.write_text(FAKE)
    fake.chmod(0o755)
    state_path, log = tmp / "state.json", tmp / "log"
    env = {**os.environ, "PATH": f"{tmp / 'bin'}:{os.environ['PATH']}", "FAKE_STATE": str(state_path),
           "FAKE_LOG": str(log), "XDG_RUNTIME_DIR": str(tmp)}

    def tile(layout: str, window: dict, *extra: str) -> tuple[int, list[str]]:
        state_path.write_text(json.dumps({"window": window, "monitors": [MONITOR]}))
        log.write_text("")
        r = subprocess.run([sys.executable, str(TILE), layout, *extra], env=env, capture_output=True, text=True)
        return r.returncode, [c.strip() for line in log.read_text().splitlines() for c in line.split(";") if c.strip()]

    def geometry(commands: list[str]) -> tuple[int, int, int, int] | None:
        size = next((re.findall(r"-?\d+", c.split(",")[0]) for c in commands if c.startswith("dispatch resizewindowpixel exact")), None)
        at = next((re.findall(r"-?\d+", c.split(",")[0]) for c in commands if c.startswith("dispatch movewindowpixel exact")), None)
        return (int(at[0]), int(at[1]), int(size[0]), int(size[1])) if size and at else None

    window = {"address": "0xabc", "at": [300, 200], "size": [800, 500], "floating": True, "monitor": 0, "fullscreen": 0}
    # Usable: x 8…1432, y 38…814 (30 menu bar + gap, 78 Dock + gap).
    expect = {
        "left": (8, 38, 708, 776), "right": (724, 38, 708, 776),
        "top": (8, 38, 1424, 384), "bottom": (8, 430, 1424, 384),
        "top-left": (8, 38, 708, 384), "bottom-right": (724, 430, 708, 384),
        "fill": (8, 38, 1424, 776), "center": (320, 176, 800, 500),
    }
    for layout, want in expect.items():
        (tmp / "gg-tile.json").unlink(missing_ok=True)
        code, commands = tile(layout, window)
        got = geometry(commands)
        check(code == 0 and got == want, f"{layout}: expected {want}, got {got} (exit {code}, {commands})")
        check(all(",address:0xabc" in c for c in commands), f"{layout}: every dispatch names the window: {commands}")

    # Neighbours share one gap, and nothing leaves the usable area.
    l, r = expect["left"], expect["right"]
    check(r[0] - (l[0] + l[2]) == 8, "left and right halves are one gap apart")
    for layout, (x, y, w, h) in expect.items():
        check(x >= 8 and y >= 38 and x + w <= 1432 and y + h <= 814, f"{layout} stays inside the usable area")

    # Return to Previous Size: the geometry from before the first tile.
    (tmp / "gg-tile.json").unlink(missing_ok=True)
    tile("left", window)
    tile("top-right", {**window, "at": [724, 38], "size": [708, 384]})
    code, commands = tile("restore", window)
    check(geometry(commands) == (300, 200, 800, 500), f"restore: back to 300,200 800×500, got {geometry(commands)}")
    code, commands = tile("restore", window)
    check(code == 0 and not commands, "restore with nothing saved does nothing")

    # A tiled (not floating) window floats first; a full-screen one is left alone.
    code, commands = tile("left", {**window, "floating": False})
    check(bool(commands) and commands[0] == "dispatch setfloating address:0xabc", f"tiled window floats first: {commands}")
    code, commands = tile("left", {**window, "fullscreen": 1})
    check(code != 0 and not commands, "a full-screen window isn't moved")
    # An explicit address (the Window menu holds focus) picks that client.
    state_path.write_text(json.dumps({"window": {}, "clients": [{**window, "address": "0xdef"}], "monitors": [MONITOR]}))
    log.write_text("")
    subprocess.run([sys.executable, str(TILE), "right", "0xdef"], env=env, capture_output=True)
    check("address:0xdef" in log.read_text(), "gg-tile LAYOUT ADDRESS tiles that window")
    # HiDPI: a 2880×1800 panel at scale 2 lays out in 1440×900.
    MONITOR.update(width=2880, height=1800, scale=2)
    code, commands = tile("fill", window)
    check(geometry(commands) == (8, 38, 1424, 776), f"scale 2 uses logical pixels: {geometry(commands)}")
    code, _ = tile("sideways", window)
    check(code == 2, "an unknown layout is refused")

conf = (ROOT / "compositor/hyprland/hyprland.conf").read_text()
for key, layout in [("left", "left"), ("right", "right"), ("up", "top"), ("down", "bottom"),
                    ("RETURN", "fill"), ("C", "center"), ("BACKSPACE", "restore")]:
    check(re.search(rf"^bind = CTRL ALT, {key}, exec, gg-tile {layout}$", conf, re.M) is not None, f"⌃⌥{key} → gg-tile {layout}")
menubar = (ROOT / "shell/MenuBar.qml").read_text()
check("id: windowMenu" in menubar and 'bar.tile("left")' in menubar and 'bar.tile("restore")' in menubar,
      "the menu bar has a Window menu with Move & Resize")
zoom = (ROOT / "apps/lib/ZoomMenu.qml").read_text()
check(all(f'layout: "{l}"' in zoom for l in ["left", "right", "top", "bottom", "top-left", "bottom-right"]),
      "the green button's menu offers halves and quarters")
check("ZoomMenu {" in (ROOT / "apps/lib/AppWindow.qml").read_text(), "AppWindow opens ZoomMenu from the green button")
install = (ROOT / "scripts/install.sh").read_text()
check(install.count('> "$BIN/gg-tile"') >= 3, "install.sh writes gg-tile in every mode")
check('["/usr/local/bin/gg-tile"]="0:0:755"' in (ROOT / "distro/archiso/build.sh").read_text(), "the ISO keeps gg-tile executable")
for name in ["left", "right", "top", "bottom", "top-left", "top-right", "bottom-left", "bottom-right", "fill", "center"]:
    check((ROOT / f"apps/lib/assets/symbols/tile-{name}.svg").exists(), f"symbol tile-{name}")

if failures:
    print("\n".join("FAIL " + f for f in failures), file=sys.stderr)
    raise SystemExit(1)
print("tiling: gg-tile layouts, gaps, restore, floating, HiDPI; keys, Window menu and green-button menu wired")
