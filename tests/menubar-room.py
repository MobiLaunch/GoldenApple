#!/usr/bin/env python3
"""The menu bar shares its room: the status items on the right come first;
the app's menus that don't fit move into » (and open from there), and the
app's name is shortened only past what fits. At 1440 px every menu shows;
at 800 px with 150% text the last ones move into ». Runs the whole shell in
the preview harness."""
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
    QTest.qWait(300)
    bar = next(o for w in QGuiApplication.topLevelWindows() for o in [w] + w.findChildren(QObject)
               if o.property("titlesShown") is not None)
    over = next(o for w in QGuiApplication.topLevelWindows() for o in w.findChildren(QObject)
                if o.objectName() == "menuBarOverflow")
    titles = bar.property("titles")
    titles = titles.toVariant() if hasattr(titles, "toVariant") else titles
    state = {"titles": titles, "shown": bar.property("titlesShown"), "overflow": over.property("visible")}
    if over.property("visible"):
        over.clicked.emit()
        QTest.qWait(100)
        state["openTitle"] = bar.property("openTitle")
    open(out, "w").write(json.dumps(state))
P.Preview.ipc = ipc
sys.exit(P.main())
'''


def run(size, scale):
    with tempfile.TemporaryDirectory() as t:
        t = Path(t)
        (t / "config/golden-gate").mkdir(parents=True)
        (t / "config/golden-gate/desktop.json").write_text(json.dumps({"textScale": scale}))
        driver = t / "driver.py"
        driver.write_text(DRIVER)
        out = t / "state.json"
        p = subprocess.run([sys.executable, str(driver), str(ROOT / "tools/preview"), str(out), "shell",
                            "--env", f"XDG_CONFIG_HOME={t / 'config'}", "--env", f"XDG_STATE_HOME={t / 'state'}",
                            "--size", size, "--do", "x.measure", "--wait", "600", "-o", str(t / "shot.png")],
                           env={**os.environ, "QT_QPA_PLATFORM": "offscreen"}, capture_output=True, text=True, timeout=240)
        if not out.exists():
            print(p.stderr[-2000:])
            return None
        return json.loads(out.read_text())


failures = []
wide = run("1440x900", 1)
narrow = run("800x600", 1.5)
if wide is None or narrow is None:
    failures.append("the shell never reported the menu bar")
else:
    if wide["shown"] != len(wide["titles"]) or wide["overflow"]:
        failures.append(f"at 1440 px every menu shows: {wide}")
    if not (0 < narrow["shown"] < len(narrow["titles"])) or not narrow["overflow"]:
        failures.append(f"at 800 px and 150% text the last menus move into »: {narrow}")
    elif narrow.get("openTitle") != narrow["titles"][narrow["shown"]] and narrow["titles"][narrow["shown"]] != "Window":
        failures.append(f"» opens the first menu it holds: {narrow}")
for f in failures:
    print("FAIL", f, file=sys.stderr)
if not failures:
    print(f"Menu bar: {wide['shown']} menus at 1440 px; {narrow['shown']} and » at 800 px with 150% text")
sys.exit(1 if failures else 0)
