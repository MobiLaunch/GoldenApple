#!/usr/bin/env python3
"""Rearranging the Dock with the pointer (shell/Dock.qml), in the preview
harness: an icon picked up stays under the pointer the whole way along
(however the shelf recentres as the others make room), holds still while
the pointer does, lands where it's let go (saved with gg-pref), and dragged
up off the Dock it's removed. The drag used to read the pointer in the
dragged icon's own coordinates, which moved with it, so the icon jumped
about and landed anywhere."""
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
from PySide6.QtCore import QObject, QPoint, QPointF, Qt
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

def items():
    for w in QGuiApplication.topLevelWindows():
        root = getattr(w, "contentItem", lambda: None)()
        stack = [root] if root is not None else []
        while stack:
            it = stack.pop()
            yield w, it
            stack.extend(it.childItems())

def kept_tiles():
    out = []
    for w, it in items():
        m = it.property("modelData")
        if it.property("lifted") is not None and it.property("kept") is True and m is not None:
            m = plain(m)
            out.append((w, it, m.get("id") if isinstance(m, dict) else m.property("id")))
    return sorted(out, key=lambda o: o[1].mapToScene(QPointF(0, 0)).x())

def icon_x(it):
    icon = [c for c in it.childItems() if c.property("launchOffset") is not None][0]
    return icon.mapToScene(QPointF(0, 0)).x()

def dock():
    return next(o for w in QGuiApplication.topLevelWindows() for o in [w] + w.findChildren(QObject)
                if o.property("dragId") is not None and o.property("baseSize") is not None)

def drag(state, key, dx_total, dy_total, steps):
    tiles = kept_tiles()
    w, t, ident = tiles[0]
    state[key + "_before"] = [i for _, _, i in tiles]
    start = t.mapToScene(QPointF(t.width() / 2, t.height() / 2))
    pos = QPoint(int(start.x()), int(start.y()))
    QTest.mousePress(w, Qt.LeftButton, Qt.NoModifier, pos)
    QTest.qWait(30)
    gaps = []
    x0 = None
    for i in range(1, steps + 1):
        p = QPoint(int(start.x() + dx_total * i / steps), int(start.y() + dy_total * i / steps))
        QTest.mouseMove(w, p)
        QTest.qWait(25)
        if t.property("lifted"):
            gap = icon_x(t) - p.x()
            if x0 is None:
                x0 = gap
            gaps.append(round(gap - x0, 1))
    # The pointer holds still: so does the icon.
    still = []
    for _ in range(6):
        QTest.mouseMove(w, p)
        QTest.qWait(30)
        still.append(round(icon_x(t), 1))
    QTest.qWait(300)                       # the shelf finishes making room
    state[key + "_settled"] = round(icon_x(t) - p.x() - (x0 or 0), 1)
    state[key + "_lifted"] = bool(t.property("lifted"))
    state[key + "_drift"] = gaps
    state[key + "_still"] = still
    state[key + "_dropSlot"] = dock().property("dropSlot")
    QTest.mouseRelease(w, Qt.LeftButton, Qt.NoModifier, p)
    QTest.qWait(400)
    state[key + "_id"] = ident
    state[key + "_saved"] = [r for r in ran if "gg-pref" in r and "dock.pinned" in r]
    state[key + "_after"] = [i for _, _, i in kept_tiles()]

def ipc(self, target, function, args):
    state = {}
    try:
        d = dock()
        step = d.property("baseSize") + 6
        drag(state, "along", step * 2.4, 0, 24)
        ran.clear()
        drag(state, "off", 0, -d.property("baseSize") * 2.2, 12)
    except Exception as e:
        state["error"] = repr(e)
    open(out, "w").write(json.dumps(state))
P.Preview.ipc = ipc
sys.exit(P.main())
'''

with tempfile.TemporaryDirectory() as t:
    t = Path(t)
    driver = t / "driver.py"
    driver.write_text(DRIVER)
    out = t / "state.json"
    p = subprocess.run([sys.executable, str(driver), str(ROOT / "tools/preview"), str(out), "shell",
                        "--env", f"XDG_CONFIG_HOME={t / 'config'}", "--env", f"XDG_STATE_HOME={t / 'state'}",
                        "--size", "1440x900", "--do", "x.drag", "--wait", "300", "-o", str(t / "shot.png")],
                       env={**os.environ, "QT_QPA_PLATFORM": "offscreen"}, capture_output=True, text=True, timeout=240)
    if not out.exists():
        print(p.stderr[-3000:])
        raise SystemExit("the shell never reported the Dock")
    s = json.loads(out.read_text())

failures = []
if "error" in s:
    failures.append(f"driver: {s['error']}")
else:
    drift = s["along_drift"]
    if not drift or max(abs(g) for g in drift) > 2 or abs(s["along_settled"]) > 2:
        failures.append(f"the icon stays under the pointer along the Dock (drift {drift}, settled {s['along_settled']})")
    if max(s["along_still"]) - min(s["along_still"]) > 0.5:
        failures.append(f"the icon holds still while the pointer does: {s['along_still']}")
    before, after, ident = s["along_before"], s["along_after"], s["along_id"]
    if after.index(ident) != 2 or [i for i in after if i != ident] != [i for i in before if i != ident]:
        failures.append(f"let go 2.4 places along, it lands third: {before} → {after}")
    if not s["along_saved"] or ident not in s["along_saved"][-1]:
        failures.append(f"the new order is saved: {s['along_saved']}")
    if max(abs(g) for g in s["off_drift"] or [99]) > 2:
        failures.append(f"dragged up, it stays under the pointer: {s['off_drift']}")
    if s["off_id"] in s["off_after"]:
        failures.append(f"dragged up off the Dock, it's removed: {s['off_after']}")
for f in failures:
    print("FAIL", f, file=sys.stderr)
if not failures:
    print(f"Dock: an icon dragged along stays under the pointer (within 2 px), holds still, lands third and is saved; dragged off, it's removed")
sys.exit(1 if failures else 0)
