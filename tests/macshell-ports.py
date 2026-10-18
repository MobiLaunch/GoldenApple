#!/usr/bin/env python3
"""CitronOS's features carried onto MacShell (docs/SHELL.md), where the preview
harness can't load MacShell itself (CI's Shell workflow runs it in Quickshell):

- the Window menu has Sequoia's Move & Resize through gg-tile, and the app menu
  Hide Others and Show All;
- menu shortcuts read as the Mac writes them (keyd makes ⌘ Ctrl for apps);
- Control Center has AirDrop, Screen Mirroring, AirPods and the quick actions,
  added once to an existing layout; its Focus is CitronOS's Focus;
- the menu bar has the Focus moon, Citron and the location arrow;
- the Dock's red badges count an app's notifications, and Mail's unread mail;
- MacShell's Light/Dark and accent follow Settings › Appearance;
- Reduce Motion stops MacShell's movement and zooms, keeping fades."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
BAR = (ROOT / "shell/macshell/MacBar.qml").read_text()
DOCK = (ROOT / "shell/macshell/MacDock.qml").read_text()
SHELL = (ROOT / "shell/macshell/MacShell.qml").read_text()
failures: list[str] = []


def check(ok: bool, what: str) -> None:
    print(("ok   " if ok else "FAIL ") + what)
    if not ok:
        failures.append(what)


# Window and app menus.
for layout in ("fill", "center", "left", "right", "top", "bottom", "top-left", "top-right", "bottom-left", "bottom-right", "restore"):
    check(f'tile("{layout}")' in BAR, f"Window › {layout} runs gg-tile {layout}")
check('["gg-tile", layout, addr]' in BAR, "…on the front window's address")
check("Bring All to Front" in BAR and "function ggBringToFront(" in BAR, "Window › Bring All to Front")
check('mi("Hide Others"' in BAR and 'mi("Show All"' in BAR, "the app menu's Hide Others and Show All")

# Shortcuts as the Mac writes them: run ggKeys itself.
start = BAR.index("    function ggKeys(sc) {")
end = BAR.index("\n    }\n", start) + 6
js = BAR[start:end].replace("    function ggKeys", "function ggKeys")
cases = {"Ctrl+Q": "⌘Q", "Ctrl+Shift+Z": "⇧⌘Z", "Ctrl+,": "⌘,", "F5": "F5", "⌃⌥←": "⌃⌥←", "Ctrl+Shift+T": "⇧⌘T", "": ""}
out = subprocess.run(["node", "-e", js + "\nconsole.log(JSON.stringify(" + json.dumps(list(cases)) + ".map(ggKeys)))"],
                     capture_output=True, text=True)
got = json.loads(out.stdout or "null") if out.returncode == 0 else None
check(got == list(cases.values()), f"menu shortcuts in Mac glyphs ({got})")

# Control Center.
for cid in ("airdrop", "mirroring", "airpods", "mission", "screenshot", "calculator", "timer", "quicknote", "lockscreen"):
    check(f'id: "{cid}"' in BAR, f"Control Center offers {cid}")
check('"gg-airdrop", "--set"' in BAR and "airdrop.json" in BAR, "AirDrop reads and sets its service's setting")
check("gg-airplay.service" in BAR and "gg-airplay.json" in BAR and "ggStopMirroring" in BAR, "Screen Mirroring drives the AirPlay Receiver")
check("GG.CitronPodsService" in BAR, "AirPods come from the CitronPods engine")
check("root.ccMigGG" in BAR and '"ccMigGG"' in BAR, "AirDrop and Screen Mirroring join an existing layout once")
check("Prefs.focusStatus.active" in BAR and '"gg-pref", "focus.session"' in BAR, "Do Not Disturb is CitronOS's Focus")
check('"notifDnd", "dnd"' not in BAR, "…not a second copy in MacShell's own settings")

# Menu bar.
check('barWidgetEnabled("citron")' in BAR and '"citron", "toggle"' in BAR, "the menu bar's Citron item")
check('root.dnd && root.barWidgetEnabled("focus")' in BAR, "the Focus moon")
check('k === "location"' in BAR and "ggLocation" in BAR and "privacy/location.py" in BAR, "the location arrow and its row")

# Dock badges.
check("function ggBadgeFor(" in BAR and "mail-badges.json" in BAR and ".badges" in BAR, "badges: notifications, Mail's unread, Settings' switch")
check("root.bar.ggBadgeFor(" in DOCK, "the Dock draws them")
pane = (ROOT / "apps/settings/panes/NotificationsPane.qml").read_text()
check("Badge application icon" in pane, "Settings › Notifications can turn an app's badges off")

# Appearance.
check("ggFollowDark" in SHELL and '"color-scheme"' in SHELL and "ggFollowAccent" in SHELL, "Light/Dark and accent follow Settings")

# Tablet mode: the top-right swipe opens Control Center, menus give way to the
# app's name, and the desktop widgets leave Tablet Home to its own.
check('objectName: "tabletControlCenterGesture"' in BAR and "PointerDevice.TouchScreen" in BAR, "tablet: the top-right swipe opens Control Center")
check('if (Prefs.tabletMode) return item.id === "app"' in BAR, "tablet: the app's name instead of the menus")
check("!Prefs.tabletMode" in (ROOT / "shell/macshell/MacWidgets.qml").read_text(), "tablet: no desktop widgets over Tablet Home")

# Reduce Motion (Settings › Accessibility): what moves or zooms stops; fades stay.
import re
moving = []
for f in sorted((ROOT / "shell/macshell").glob("*.qml")):
    if f.name == "ClockApp.qml":       # the clocks' hands keep time
        continue
    for m in re.finditer(r"Behavior on ([A-Za-z_.]+)\s*\{([^\n]*\n?[^\n]*)", f.read_text()):
        if m.group(1) not in ("opacity", "color", "border.color", "ac") and "Theme.reduceMotion" not in m.group(2):
            moving.append(f"{f.name}:{m.group(1)}")
check(not moving, f"MacShell's motion follows Reduce Motion ({moving[:5]})")
check("Binding { target: Theme; property: \"reduceMotion\"" in (ROOT / "shell/shell.qml").read_text(), "…which the shell takes from Settings")

# The location watcher, for real: a helper's file names the app, a stale one goes.
with tempfile.TemporaryDirectory() as tmp:
    run = Path(tmp) / "citron-location"
    run.mkdir()
    (run / "weather.json").write_text(json.dumps({"app": "Weather", "pid": os.getpid(), "until": time.time() + 60}))
    (run / "gone.json").write_text(json.dumps({"app": "Old", "pid": 2 ** 22 + 1, "until": 0}))
    p = subprocess.Popen([sys.executable, str(ROOT / "apps/lib/privacy/location.py")], env={**os.environ, "XDG_RUNTIME_DIR": tmp},
                         stdout=subprocess.PIPE, text=True)
    try:
        line = p.stdout.readline()
    finally:
        p.kill()
    check(json.loads(line or "null") == ["Weather"], f"location.py names the app locating ({line.strip()})")
    check(not (run / "gone.json").exists(), "…and removes what a finished helper left")

if failures:
    sys.exit(1)
print("MacShell ports: Window menu, shortcuts, Control Center, Focus, menu bar, badges, appearance, Reduce Motion")
