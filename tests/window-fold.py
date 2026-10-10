#!/usr/bin/env python3
"""Closing a window is the opening in reverse (shell/AppLaunch.qml), as when
an iPad app is swiped away: a card in the window's colour with the app's
icon starts on the window's last frame and springs down into the app's Dock
icon, the colour fading as the icon grows to fill it, and then it's gone.
A window on another desktop, or of an app with no Dock icon, just fades
(Hyprland's windowsOut). Runs the whole shell in the preview harness with
its sample windows."""
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
from PySide6.QtCore import QObject, QMetaObject, Q_ARG, Q_RETURN_ARG, QPointF
from PySide6.QtGui import QGuiApplication
from PySide6.QtTest import QTest

def find(pred):
    return next(o for w in QGuiApplication.topLevelWindows() for o in [w] + w.findChildren(QObject) if pred(o))

def plain(v):
    return v.toVariant() if hasattr(v, "toVariant") else v

def close(launcher, address):
    r = QMetaObject.invokeMethod(launcher, "windowClosed", Q_RETURN_ARG("QVariant"), Q_ARG("QVariant", address))
    return plain(r)

def ipc(self, target, function, args):
    state = {}
    try:
        launcher = find(lambda o: o.property("frames") is not None and o.property("state_") is not None)
        card = find(lambda o: o.objectName() == "launchCard")
        state["frames"] = sorted(plain(launcher.property("frames")).keys())
        state["native_close"] = close(launcher, "0x5a5a1")
        launcher.setProperty("foldOnClose", True)  # Legacy effect is explicitly opt-in.
        state["folded"] = close(launcher, "0x5a5a1")          # Files, on this desktop
        seen = []
        for _ in range(45):
            seen.append([round(card.property(k), 1) for k in ("x", "y", "width", "height", "opacity")] + [launcher.property("state_")])
            QTest.qWait(20)
        state["seen"] = seen
        QTest.qWait(600)
        state["after"] = launcher.property("state_")
        dock = find(lambda o: o.property("tiles") is not None and o.property("baseSize") is not None)
        icon = plain(QMetaObject.invokeMethod(dock, "iconFor", Q_RETURN_ARG("QVariant"), Q_ARG("QVariant", "org.goldengate.Files")))
        r = icon["rect"]
        state["icon"] = [r.x(), launcher.property("height") + r.y(), r.width(), r.height()]
        state["screen"] = launcher.property("height")
        state["other_desktop"] = close(launcher, "0x5a5a5")    # Web, on desktop 2
        state["unknown"] = close(launcher, "0xdeadbeef")
    except Exception as e:
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
                        "--env", "GG_PREVIEW_WINDOWS=1", "--size", "1440x900", "--do", "x.fold", "--wait", "300",
                        "-o", str(t / "shot.png")],
                       env={**os.environ, "QT_QPA_PLATFORM": "offscreen"}, capture_output=True, text=True, timeout=240)
    if not out.exists():
        print(p.stderr[-3000:])
        raise SystemExit("the shell never reported")
    s = json.loads(out.read_text())

failures = []
if "error" in s:
    failures.append(s["error"])
else:
    if s["native_close"]:
        failures.append("default close must leave the compositor's fade unobstructed")
    seen = s["seen"]
    first, icon = seen[0], s["icon"]
    if not s["folded"]:
        failures.append(f"closing a window whose app is in the Dock folds it: {s}")
    elif first[:4] != [90, 80, 880, 560] or first[4] < 0.99:
        failures.append(f"the card starts on the window's last frame, opaque: {first}")
    widths = [f[2] for f in seen if f[5] == "closing"]
    if any(b > a + 0.5 for a, b in zip(widths, widths[1:])):
        failures.append(f"it only shrinks on the way home: {widths}")
    if not (s["screen"] - 120 < icon[1] < s["screen"] - icon[3]):
        failures.append(f"the Dock icon is at the bottom of the screen ({s['screen']} px): {icon}")
    near = [f for f in seen if abs(f[0] - icon[0]) < 3 and abs(f[1] - icon[1]) < 3 and abs(f[2] - icon[2]) < 3]
    if not near:
        failures.append(f"it lands on the Dock icon {icon}: last {seen[-1]}")
    if s["after"] != "idle":
        failures.append(f"then it's gone: {s['after']}")
    if s["other_desktop"] or s["unknown"]:
        failures.append(f"a window on another desktop, or not known, only fades: {s['other_desktop']}, {s['unknown']}")
for f in failures:
    print("FAIL", f, file=sys.stderr)
if not failures:
    print(f"Closing: the window folds from its frame {seen[0][:4]} into its Dock icon {[round(v) for v in icon]}, then goes")
sys.exit(1 if failures else 0)
