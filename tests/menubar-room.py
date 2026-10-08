#!/usr/bin/env python3
"""The menu bar shares its room: the status items on the right come first;
the app's menus that don't fit move into », and the app's name is
shortened only past what fits. At 1440 px every menu shows; at 800 px with
150% text the last ones move into », which lists every one of them, each
opening its own menu: the keyboard reaches an action in the last one and
runs it. At 560 px the status items give way too, and » still works. Runs
the whole shell in the preview harness."""
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
from PySide6.QtCore import QObject, Qt
from PySide6.QtGui import QGuiApplication
from PySide6.QtTest import QTest

ran = []
log = P.Preview.log
def logged(self, text):
    ran.append(text)
    log(self, text)
P.Preview.log = P.Slot(str)(logged)

def plain(v):
    return v.toVariant() if hasattr(v, "toVariant") else v

def ipc(self, target, function, args):
    try:
        measure()
    except Exception as e:
        open(out, "w").write(json.dumps({"error": repr(e)}))
        raise

def measure():
    QTest.qWait(300)
    bar = next(o for w in QGuiApplication.topLevelWindows() for o in [w] + w.findChildren(QObject)
               if o.property("titlesShown") is not None)
    over = next(o for w in QGuiApplication.topLevelWindows() for o in w.findChildren(QObject)
                if o.objectName() == "menuBarOverflow")
    titles = bar.property("titles")
    titles = titles.toVariant() if hasattr(titles, "toVariant") else titles
    state = {"titles": titles, "shown": bar.property("titlesShown"), "overflow": over.property("visible")}
    state["hidden"] = plain(over.property("hidden"))
    if over.property("visible"):
        over.clicked.emit()
        QTest.qWait(100)
        state["openTitle"] = bar.property("openTitle")
        menu = next(o for w in QGuiApplication.topLevelWindows() for o in [w] + w.findChildren(QObject)
                    if o.objectName() == "menuBarMenu")
        state["menuOpen"] = menu.property("open")
        lst = next(o for o in menu.findChildren(QObject) if o.property("isSubmenu") is False)
        items = plain(lst.property("items"))
        state["listed"] = [i.get("label") for i in items]
        state["submenus"] = [len(i.get("submenu") or []) for i in items]
        # The keyboard: down to the last title, Right into its menu, up to
        # its last item (wrapping), Return.
        win = lst.window()
        before = len(ran)
        for _ in items:
            QTest.keyClick(win, Qt.Key_Down)
        state["selected"] = state["listed"][lst.property("selected")]
        QTest.keyClick(win, Qt.Key_Right)
        QTest.qWait(50)
        QTest.keyClick(win, Qt.Key_Up)              # from the first item, up wraps to the last
        QTest.keyClick(win, Qt.Key_Return)
        QTest.qWait(500)
        state["ran"] = [r for r in ran[before:] if r.startswith("exec ") or "dispatch" in r]
        state["menuClosed"] = not menu.property("open")
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


def check_overflow(name, state):
    if not state["overflow"] or len(state["hidden"]) < 2:
        failures.append(f"{name}: two or more menus move into »: {state}")
        return
    if state.get("openTitle") != "»" or not state.get("menuOpen"):
        failures.append(f"{name}: » opens its own menu: {state}")
    if state.get("listed") != state["hidden"]:
        failures.append(f"{name}: » lists every hidden menu, in order: {state}")
    if not all(state.get("submenus") or [0]):
        failures.append(f"{name}: each title in » opens that menu: {state}")
    if state.get("selected") != state["hidden"][-1] or not state.get("ran"):
        failures.append(f"{name}: the keyboard runs an action from the last hidden menu: {state}")
    if not state.get("menuClosed"):
        failures.append(f"{name}: the menu closes once an action runs: {state}")


failures = []
wide = run("1440x900", 1)
narrow = run("800x600", 1.5)
tiny = run("560x480", 1.5)
if wide is None or narrow is None or tiny is None:
    failures.append("the shell never reported the menu bar")
else:
    if wide["shown"] != len(wide["titles"]) or wide["overflow"]:
        failures.append(f"at 1440 px every menu shows: {wide}")
    if not (0 < narrow["shown"] < len(narrow["titles"])):
        failures.append(f"at 800 px and 150% text the last menus move into »: {narrow}")
    check_overflow("800 px", narrow)
    check_overflow("560 px", tiny)
for f in failures:
    print("FAIL", f, file=sys.stderr)
if not failures:
    print(f"Menu bar: {wide['shown']} menus at 1440 px; {narrow['shown']} and » ({len(narrow['hidden'])} menus) at 800 px "
          f"with 150% text; {tiny['shown']} and » ({len(tiny['hidden'])}) at 560 px; ran {narrow['ran'][-1]}")
sys.exit(1 if failures else 0)
