#!/usr/bin/env python3
"""The shell follows Settings → Notifications: an app that isn't allowed is
dropped, one without banners still reaches Notification Center, a badge can
be turned off, and every app that notifies is remembered for Settings to
list. Runs the whole shell in the preview harness."""
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
from PySide6.QtCore import QObject, QMetaObject, Q_ARG, Q_RETURN_ARG
from PySide6.QtGui import QGuiApplication

def ipc(self, target, function, args):
    if function == "send":
        for i, (app, entry) in enumerate([("Messages", "org.goldengate.Messages"), ("Mail", "org.goldengate.Mail"),
                                          ("Calendar", "org.goldengate.Calendar")]):
            self.notify({"id": 10 + i, "appName": app, "desktopEntry": entry, "appIcon": entry,
                         "summary": app + " says hi", "body": "Hello"})
        return
    n = None
    for w in QGuiApplication.topLevelWindows():
        n = w.findChild(QObject, "notifications") or n
    def value(name):
        v = n.property(name)
        return v.toVariant() if hasattr(v, "toVariant") else v
    state = {
        "tracked": sorted(x.property("appName") for x in value("list")),
        "banners": sorted(x.property("appName") for x in value("banners")),
        "notifiers": value("notifiers"),
    }
    for app in ("org.goldengate.Mail", "org.goldengate.Calendar"):
        r = QMetaObject.invokeMethod(n, "countFor", Q_RETURN_ARG("QVariant"), Q_ARG("QVariant", app), Q_ARG("QVariant", ""))
        state["badge:" + app] = r
    open(out, "w").write(json.dumps(state))
P.Preview.ipc = ipc
sys.exit(P.main())
'''


def main() -> int:
    with tempfile.TemporaryDirectory() as t:
        t = Path(t)
        (t / "config/golden-gate").mkdir(parents=True)
        (t / "config/golden-gate/desktop.json").write_text(json.dumps({"notifications": {"apps": {
            "org.goldengate.messages": {"allow": False},
            "org.goldengate.mail": {"banners": False, "badges": False}}}}))
        driver = t / "driver.py"
        driver.write_text(DRIVER)
        out = t / "state.json"
        env = {**os.environ, "QT_QPA_PLATFORM": "offscreen"}
        p = subprocess.run([sys.executable, str(driver), str(ROOT / "tools/preview"), str(out), "shell",
                            "--env", f"XDG_CONFIG_HOME={t / 'config'}", "--env", f"XDG_STATE_HOME={t / 'state'}",
                            "--do", "x.send", "--do", "x.dump", "--wait", "700", "-o", str(t / "shot.png")],
                           env=env, capture_output=True, text=True, timeout=180)
        if not out.exists():
            print(p.stderr[-3000:])
            print("notification settings: the shell never reported its state")
            return 1
        state = json.loads(out.read_text())
        failures = []
        if "Messages" in state["tracked"]:
            failures.append(f"Messages isn't allowed, yet it was kept: {state['tracked']}")
        if "Mail" not in state["tracked"]:
            failures.append(f"Mail has no banners but belongs in Notification Center: {state['tracked']}")
        if state["banners"] != ["Calendar"]:
            failures.append(f"only Calendar shows a banner: {state['banners']}")
        if state["badge:org.goldengate.Mail"] != 0 or state["badge:org.goldengate.Calendar"] != 1:
            failures.append(f"badges: Mail off, Calendar on: {state}")
        if set(state["notifiers"]) != {"org.goldengate.messages", "org.goldengate.mail", "org.goldengate.calendar"}:
            failures.append(f"every app that notified is remembered, even one not allowed: {state['notifiers']}")
        for f in failures:
            print("FAIL:", f)
        if failures:
            return 1
        print("Notification settings: allow, banners, badges and the list of apps work in the shell")
        return 0


if __name__ == "__main__":
    sys.exit(main())
