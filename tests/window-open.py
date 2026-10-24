#!/usr/bin/env python3
"""Opening an app (shell/AppLaunch.qml): the card grows from the icon, springs
onto the window's real frame and only then dissolves into it, sitting
exactly on it. It used to start fading on a timer while still springing
there, so for a moment a sliding card and the window showed two outlines.
Hyprland fades the window in where it is (windowsIn popin 100%), so nothing
under the card changes size either."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]

DRIVER = r'''
import json, sys
sys.path.insert(0, sys.argv.pop(1))
out = sys.argv.pop(1)
import preview as P
from PySide6.QtCore import QObject, QMetaObject, Q_ARG, QRectF
from PySide6.QtGui import QGuiApplication
from PySide6.QtTest import QTest

def find(pred):
    return next(o for w in QGuiApplication.topLevelWindows() for o in [w] + w.findChildren(QObject) if pred(o))

def ipc(self, target, function, args):
    state = {}
    try:
        launcher = find(lambda o: o.property("frames") is not None and o.property("state_") is not None)
        card = find(lambda o: o.objectName() == "launchCard")
        dock = find(lambda o: o.property("tiles") is not None and o.property("baseSize") is not None)
        entry = dock.property("entries").toVariant()[0] if hasattr(dock.property("entries"), "toVariant") else dock.property("entries")[0]
        QMetaObject.invokeMethod(launcher, "launch", Q_ARG("QVariant", entry), Q_ARG("QVariant", QRectF(300, 830, 54, 54)))
        QTest.qWait(120)
        # The window turns up somewhere other than where the card was going.
        frame = QRectF(160, 90, 700, 480)
        QMetaObject.invokeMethod(launcher, "landOn", Q_ARG("QVariant", frame))
        seen = []
        for _ in range(60):
            seen.append([round(card.property(k), 1) for k in ("x", "y", "width", "height", "opacity")])
            QTest.qWait(16)
        state["seen"] = seen
        state["frame"] = [frame.x(), frame.y(), frame.width(), frame.height()]
        state["after"] = launcher.property("state_")
    except Exception:
        import traceback
        state["error"] = traceback.format_exc()
    open(out, "w").write(json.dumps(state))
P.Preview.ipc = ipc
sys.exit(P.main())
'''

with tempfile.TemporaryDirectory() as t:
    t = Path(t)
    (t / "driver.py").write_text(DRIVER)
    out = t / "state.json"
    p = subprocess.run([sys.executable, str(t / "driver.py"), str(ROOT / "tools/preview"), str(out), "shell",
                        "--env", f"XDG_CONFIG_HOME={t / 'config'}", "--env", f"XDG_STATE_HOME={t / 'state'}",
                        "--size", "1440x900", "--do", "x.open", "--wait", "300", "-o", str(t / "shot.png")],
                       env={**os.environ, "QT_QPA_PLATFORM": "offscreen"}, capture_output=True, text=True, timeout=240)
    if not out.exists():
        print(p.stderr[-3000:])
        raise SystemExit("the shell never reported")
    s = json.loads(out.read_text())

failures = []
if "error" in s:
    failures.append(s["error"])
else:
    fx, fy, fw, fh = s["frame"]
    fading = [f for f in s["seen"] if f[4] < 0.98]
    moving_fade = [f for f in fading if max(abs(f[0] - fx), abs(f[1] - fy), abs(f[2] - fw), abs(f[3] - fh)) > 1.5]
    if not fading:
        failures.append(f"the card dissolves into the window: {s['seen'][-3:]}")
    if moving_fade:
        failures.append(f"it fades only once it sits on the window's frame {s['frame']}, not on its way: {moving_fade[:3]}")
    if s.get("after") != "idle":
        failures.append(f"then it's gone: {s.get('after')}")
motion = (ROOT / "design/dist/hyprland-motion.conf").read_text()
if not re.search(r"animation = windowsIn, 1, [\d.]+, \w+, popin 100%", motion):
    failures.append("Hyprland fades a new window in where it is (windowsIn popin 100%)")
for f in failures:
    print("FAIL", f, file=sys.stderr)
if not failures:
    print(f"Opening: the card lands on the window's frame {s['frame']}, then dissolves into it in place")
sys.exit(1 if failures else 0)
