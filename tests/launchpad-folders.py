#!/usr/bin/env python3
"""Launchpad's strict curated icon policy: unmatched Linux apps are never
shown, including in the old Other folder. Golden Gate system tools remain
inside Utilities. Runs the shell in the preview harness."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]

DRIVER = r'''
import json, sys
sys.path.insert(0, sys.argv.pop(1))
out = sys.argv.pop(1)
import preview as P
from PySide6.QtCore import QObject
from PySide6.QtGui import QGuiApplication
from PySide6.QtTest import QTest

def ipc(self, target, function, args):
    QTest.qWait(600)
    apps = next(o for w in QGuiApplication.topLevelWindows() for o in [w] + w.findChildren(QObject)
                if o.property("firstPartyUtilities") is not None)
    entries = apps.property("entries")
    entries = entries.toVariant() if hasattr(entries, "toVariant") else entries
    def ident(e):
        return e.get("id") if isinstance(e, dict) else e.property("id")
    state = {"grid": [], "folders": {}}
    for e in entries:
        if isinstance(e, dict) and e.get("isFolder"):
            state["folders"][e["name"]] = [ident(a) for a in e["apps"]]
            state["grid"].append(e["id"])
        else:
            state["grid"].append(ident(e))
    open(out, "w").write(json.dumps(state))
P.Preview.ipc = ipc
sys.exit(P.main())
'''

with tempfile.TemporaryDirectory() as t:
    t = Path(t)
    (t / "config/golden-gate").mkdir(parents=True)
    data = t / "data/applications"
    data.mkdir(parents=True)
    # Stand-ins for apps a system brings along.
    for ident, cats in (("htop", "System;Monitor;"), ("org.gnome.Settings", "Settings;DesktopSettings;"),
                        ("xterm", "System;TerminalEmulator;"), ("gimp", "Graphics;"), ("org.example.Unzip", "Utility;Archiving;")):
        (data / f"{ident}.desktop").write_text(f"[Desktop Entry]\nType=Application\nName={ident}\nExec=true\nIcon={ident}\nCategories={cats}\n")
    driver = t / "driver.py"
    driver.write_text(DRIVER)
    out = t / "state.json"
    env = {**os.environ, "QT_QPA_PLATFORM": "offscreen", "GG_PREVIEW_APPLICATIONS": str(data)}
    p = subprocess.run([sys.executable, str(driver), str(ROOT / "tools/preview"), str(out), "shell",
                        "--env", f"XDG_CONFIG_HOME={t / 'config'}", "--env", f"XDG_STATE_HOME={t / 'state'}",
                        "--do", "x.look", "--wait", "800", "-o", str(t / "shot.png")],
                       env=env, capture_output=True, text=True, timeout=240)
    if not out.exists():
        print(p.stderr[-2000:])
        sys.exit("launchpad: the shell never reported its grid")
    s = json.loads(out.read_text())

failures = []
util = s["folders"].get("Utilities", [])
for ident in ("org.goldengate.Terminal", "org.goldengate.DiskUtility"):
    if ident not in util:
        failures.append(f"Missing native utility with curated icon: {ident} ({util})")
for ident in ("htop", "org.gnome.Settings", "xterm", "org.example.Unzip", "gimp"):
    if ident in s["grid"] or ident in util or any(ident in ids for ids in s["folders"].values()):
        failures.append(f"Unmatched Linux app leaked into Launchpad: {ident}")
for ident in ("org.goldengate.Terminal", "org.goldengate.DiskUtility"):
    if ident in s["grid"]:
        failures.append(f"{ident} isn't also loose on the grid")
if "Other" in s["folders"]:
    failures.append("Other folder must not expose apps without curated icons")
if "org.goldengate.Files" not in s["grid"]:
    failures.append("CitronOS's own apps stay on the grid")
for f in failures:
    print("FAIL", f, file=sys.stderr)
if not failures:
    print(f"Launchpad: Utilities holds {len(util)} curated icons; unmatched apps excluded")
sys.exit(1 if failures else 0)
