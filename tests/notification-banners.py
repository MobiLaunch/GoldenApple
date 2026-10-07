#!/usr/bin/env python3
"""Banners move as on the Mac: a new one slides in from the screen's edge, a
dropped one slides back out (it doesn't vanish in a frame, and keeps what it
says while it goes), and the banners below it move up into its place.
Opening Notification Center, its groups cascade in. Runs the whole shell in
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
from PySide6.QtCore import QObject, QMetaObject, Q_ARG
from PySide6.QtGui import QGuiApplication
from PySide6.QtTest import QTest

state = {}

def find(name):
    for w in QGuiApplication.topLevelWindows():
        o = w.findChild(QObject, name)
        if o is not None:
            return o

def cards(view):
    """The banner cards, top to bottom: (y, x, opacity, title)."""
    # Delegates are the visual children of the view's content item.
    items = [c for c in view.property("contentItem").childItems()
             if c.property("nid") is not None and c.property("title") is not None and c.property("visible")]
    return sorted((c.property("y"), c.property("x"), c.property("opacity"), c.property("title")) for c in items)

def groups():
    """Notification Center's groups: how far each has come in (0…1)."""
    out = []
    for w in QGuiApplication.topLevelWindows():
        root = w.contentItem()
        stack = [root]
        while stack:
            it = stack.pop()
            stack.extend(it.childItems())
            if it.property("shown") is not None and it.property("modelData") is not None and it.property("open") is not None:
                out.append(round(it.property("shown"), 2))
    return out

def ipc(self, target, function, args):
    view = find("bannerList")
    if function == "send":
        self.notify({"id": 21, "appName": "Calendar", "desktopEntry": "org.goldengate.Calendar",
                     "summary": "Design review", "body": "Today at 10:30"})
        QTest.qWait(40)
        state["arriving"] = cards(view)
        return
    if function == "second":
        self.notify({"id": 22, "appName": "Mail", "desktopEntry": "org.goldengate.Mail",
                     "summary": "Ferry tickets", "body": "Your booking"})
        return
    if function == "drop":
        n = find("notifications")
        state["before"] = cards(view)
        older = [b for b in n.property("banners").toVariant() if b.property("summary") == "Design review"][0]
        QMetaObject.invokeMethod(n, "dropBanner", Q_ARG("QVariant", older))
        QTest.qWait(90)
        state["leaving"] = cards(view)
        QTest.qWait(900)
        state["after"] = cards(view)
        # Notification Center: its groups cascade in.
        n.setProperty("centerOpen", True)
        QTest.qWait(30)
        state["cascade"] = groups()
        QTest.qWait(1200)
        state["settled"] = groups()
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
                            "--do", "x.send", "--do", "x.second", "--do", "x.drop", "--wait", "900", "-o", str(t / "shot.png")],
                           env=env, capture_output=True, text=True, timeout=180)
        if not out.exists():
            print(p.stderr[-3000:])
            print("notification banners: the shell never reported its state")
            return 1
        s = json.loads(out.read_text())
        failures = []
        if not s["arriving"] or s["arriving"][0][1] < 40:
            failures.append(f"a new banner starts off at the screen's edge and slides in: {s['arriving']}")
        before = {c[3]: c for c in s["before"]}
        if set(before) != {"Design review", "Ferry tickets"} or before["Ferry tickets"][0] >= before["Design review"][0]:
            failures.append(f"two banners, the newest on top, both in place: {s['before']}")
        elif any(abs(c[1]) > 0.5 for c in s["before"]):
            failures.append(f"banners that have arrived sit at x 0: {s['before']}")
        leaving = {c[3]: c for c in s["leaving"]}
        if "Design review" not in leaving:
            failures.append(f"a dropped banner slides out rather than vanishing at once: {s['leaving']}")
        else:
            y, x, opacity, _ = leaving["Design review"]
            if not (x > 1 and opacity < 1):
                failures.append(f"…moving right and fading as it goes: x {x}, opacity {opacity}")
        if [c[3] for c in s["after"]] != ["Ferry tickets"]:
            failures.append(f"then it's gone, the other stays: {s['after']}")
        if not s["cascade"] or max(s["cascade"]) > 0.5:
            failures.append(f"opening Notification Center, its groups start out of place and cascade in: {s['cascade']}")
        if not s["settled"] or min(s["settled"]) < 1:
            failures.append(f"…and all arrive: {s['settled']}")
        if failures:
            print("\n".join("FAIL " + f for f in failures), file=sys.stderr)
            return 1
        print("Notification banners: slide in from the edge, slide out when dropped, keep their words as they go; Notification Center cascades in")
        return 0


if __name__ == "__main__":
    sys.exit(main())
