#!/usr/bin/env python3
"""The Dock's icons move as on the Mac: an app's icon keeps bouncing while it
opens and always lands, an app asking for attention bounces until one of its
windows comes forward, and a notification badge pops in. Runs the whole shell
in the preview harness."""
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
from PySide6.QtQml import QQmlEngine, QQmlExpression

state = {}

def items():
    for w in QGuiApplication.topLevelWindows():
        root = getattr(w, "contentItem", lambda: None)()
        stack = [root] if root is not None else []
        while stack:
            it = stack.pop()
            yield it
            stack.extend(it.childItems())

def tile(app):
    for it in items():
        m = it.property("modelData")
        if it.property("hopping") is not None and m is not None:
            m = m.toVariant() if hasattr(m, "toVariant") else m
            ident = m.get("id") if isinstance(m, dict) else m.property("id")
            if ident == app:
                return it

def offsets(t, ms):
    icon = [c for c in t.childItems() if c.property("launchOffset") is not None][0]
    seen = []
    for _ in range(ms // 20):
        QTest.qWait(20)
        seen.append(round(icon.property("launchOffset"), 1))
    return seen

def ipc(self, target, function, args):
    if function == "launch":
        t = tile("org.goldengate.Files")
        t.setProperty("launching", True)
        state["launching"] = offsets(t, 1200)
        t.setProperty("launching", False)
        state["landing"] = offsets(t, 700)
    elif function == "attention":
        t = tile("org.goldengate.Mail")
        # The Dock (a PanelWindow) keeps the apps asking for attention.
        dock = next(o for win in QGuiApplication.topLevelWindows() for o in [win] + win.findChildren(QObject)
                    if o.property("attention") is not None and o.property("baseSize") is not None)
        dock.setProperty("attention", ["org.goldengate.mail"])
        state["asking"] = offsets(t, 900)
        dock.setProperty("attention", [])
        state["answered"] = offsets(t, 700)
    elif function == "activate":
        t = tile("org.goldengate.Files")
        expression = QQmlExpression(QQmlEngine.contextForObject(t), t, "pulseActivation()")
        expression.evaluate()
        if expression.hasError():
            raise RuntimeError(expression.error().toString())
        icon = next(c for c in t.childItems() if c.property("activationLift") is not None)
        values = []
        for _ in range(25):
            QTest.qWait(20)
            values.append(round(icon.property("activationLift"), 2))
        state["activation"] = values
    elif function == "badge":
        self.notify({"id": 31, "appName": "Mail", "desktopEntry": "org.goldengate.Mail",
                     "summary": "Ferry tickets", "body": "Your booking"})
        t = tile("org.goldengate.Mail")
        dot = [c for c in t.childItems() if c.property("bump") is not None][0]
        seen = []
        for _ in range(40):
            QTest.qWait(20)
            seen.append(round(dot.property("scale"), 2))
        state["badge"] = seen
        open(out, "w").write(json.dumps(state))
P.Preview.ipc = ipc
sys.exit(P.main())
'''


def main() -> int:
    with tempfile.TemporaryDirectory() as t:
        t = Path(t)
        (t / "config/golden-gate").mkdir(parents=True)
        driver = t / "driver.py"
        driver.write_text(DRIVER)
        out = t / "state.json"
        env = {**os.environ, "QT_QPA_PLATFORM": "offscreen"}
        p = subprocess.run([sys.executable, str(driver), str(ROOT / "tools/preview"), str(out), "shell",
                            "--env", f"XDG_CONFIG_HOME={t / 'config'}", "--env", f"XDG_STATE_HOME={t / 'state'}",
                            "--do", "x.launch", "--do", "x.attention", "--do", "x.activate", "--do", "x.badge", "--wait", "600", "-o", str(t / "shot.png")],
                           env=env, capture_output=True, text=True, timeout=240)
        if not out.exists():
            print(p.stderr[-3000:])
            print("dock motion: the shell never reported its state")
            return 1
        s = json.loads(out.read_text())
        failures = []
        hops = s["launching"]
        tops = sum(1 for a, b, c in zip(hops, hops[1:], hops[2:]) if b < a and b <= c and b < -10)
        if tops < 2:
            failures.append(f"an opening app's icon keeps bouncing (≥2 hops in 1.2 s): {hops}")
        if s["landing"][-1] != 0:
            failures.append(f"…and lands when its window shows: {s['landing']}")
        if min(s["asking"]) > -10:
            failures.append(f"an app asking for attention bounces: {s['asking']}")
        if s["answered"][-1] != 0:
            failures.append(f"…and settles once it's answered: {s['answered']}")
        lift = s["activation"]
        if max(lift) < 4 or abs(lift[-1]) > 0.1:
            failures.append(f"existing-window activation should briefly lift and settle: {lift}")
        badge = s["badge"]
        if not badge or badge[0] > 0.9 or abs(badge[-1] - 1) > 0.02:
            failures.append(f"the badge grows in rather than appearing at full size: {badge}")
        if failures:
            print("\n".join("FAIL " + f for f in failures), file=sys.stderr)
            return 1
        print("Dock: opening/attention bounces, brief existing-app activation lift, and badge motion")
        return 0


if __name__ == "__main__":
    sys.exit(main())
