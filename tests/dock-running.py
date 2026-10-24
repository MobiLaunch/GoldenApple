#!/usr/bin/env python3
"""Every app with a window open is in the Dock, as on the Mac (shell/Dock.qml):
the kept ones with their running dot, and the rest after a divider, whether
or not their desktop entry is found. One with no entry at all (a script, an
AppImage) gets a stand-in, named from its window's id, that opens its window
and can't be kept (nothing would open it again). Apps whose entry couldn't
be found used to be left out of the Dock."""
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

def plain(v):
    return v.toVariant() if hasattr(v, "toVariant") else v

def dock():
    return next(o for w in QGuiApplication.topLevelWindows() for o in [w] + w.findChildren(QObject)
                if o.property("dragId") is not None and o.property("baseSize") is not None)

def ipc(self, target, function, args):
    state = {}
    try:
        d = dock()
        state["running"] = [{"id": plain(e).get("id") if isinstance(plain(e), dict) else e.property("id"),
                             "name": plain(e).get("name") if isinstance(plain(e), dict) else e.property("name"),
                             "synthetic": bool(plain(e).get("synthetic")) if isinstance(plain(e), dict) else False}
                            for e in plain(d.property("running"))]
    except Exception as e:
        state["error"] = repr(e)
    open(out, "w").write(json.dumps(state))
P.Preview.ipc = ipc
sys.exit(P.main())
'''


def main():
    with tempfile.TemporaryDirectory() as t:
        t = Path(t)
        driver = t / "driver.py"
        driver.write_text(DRIVER)
        out = t / "state.json"
        running = "org.goldengate.Files,org.goldengate.Clock,org.goldengate.DiskUtility,com.example.night-owl_tool"
        p = subprocess.run([sys.executable, str(driver), str(ROOT / "tools/preview"), str(out), "shell",
                            "--env", f"XDG_CONFIG_HOME={t / 'config'}", "--env", f"GG_PREVIEW_RUNNING={running}",
                            "--do", "dock.check", "-o", str(t / "shot.png")],
                           env={**os.environ, "QT_QPA_PLATFORM": "offscreen"}, capture_output=True, text=True, timeout=240)
        if not out.exists():
            print(p.stdout[-2000:], p.stderr[-3000:], file=sys.stderr)
            print("FAIL the preview didn't run the check", file=sys.stderr)
            return 1
        state = json.loads(out.read_text())
    failures = []
    if "error" in state:
        failures.append(state["error"])
    ids = [e["id"] for e in state.get("running", [])]
    # Files is kept in the Dock by default: shown there, not again.
    if "org.goldengate.Files" in ids:
        failures.append(f"a kept app isn't shown twice: {ids}")
    for app in ("org.goldengate.Clock", "org.goldengate.DiskUtility"):
        if app not in ids:
            failures.append(f"{app}, running and not kept, is in the Dock: {ids}")
    stand = [e for e in state.get("running", []) if e["id"] == "com.example.night-owl_tool"]
    if not stand or not stand[0]["synthetic"] or stand[0]["name"] != "Night Owl Tool":
        failures.append(f"an app with no desktop entry gets a stand-in named from its id: {stand}")
    dock = (ROOT / "shell/Dock.qml").read_text()
    if '!entry.synthetic)\n            menu.push({ label: kept ? "Remove from Dock" : "Keep in Dock"' not in dock:
        failures.append("a stand-in's menu has no Keep in Dock")
    if "&& !tile.modelData.synthetic" not in dock:
        failures.append("a stand-in can't be dragged in among the kept apps")
    for f in failures:
        print("FAIL", f, file=sys.stderr)
    if not failures:
        print(f"Dock: every running app shown ({', '.join(ids)}); a stand-in for one with no entry; kept apps not twice")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
