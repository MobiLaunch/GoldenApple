#!/usr/bin/env python3
"""Settings › Displays changes a display's scale without losing the layout
(apps/settings/panes/DisplaysPane.qml, with Hyprland stood in for): the
display keeps its position and exact mode, a display to its right moves by
however much it grew or shrank, only scales its resolution divides into
are offered, a scale Hyprland won't take is put back at once, and a change
is written to displays.conf only after Keep Changes; otherwise it reverts
by itself, through a watchdog process of its own, so closing Settings or
leaving the pane doesn't keep an unconfirmed change; and a Keep whose
save fails puts the previous settings back."""
import os
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
import json
from pathlib import Path
import re
import sys
import tempfile
import unittest

from PySide6.QtCore import QMetaObject, QObject, QUrl, Q_ARG, Slot
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlExpression
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/preview"))
import preview
APP = QGuiApplication([])


class Hypr(preview.Preview):
    def __init__(self, env, refuse=False, write_fails=False):
        super().__init__(env, str(ROOT / "apps"), "'default'")
        self.refuse = refuse
        self.write_fails = write_fails
        self.ran = []
        self.armed = {}                 # watchdog token → the rules it would put back
        self.verbose = True
        self.mons = [
            {"name": "eDP-1", "description": "Built-in Display", "width": 2560, "height": 1600, "refreshRate": 59.99900,
             "x": 0, "y": 0, "scale": 1.0},
            {"name": "DP-1", "description": "Studio Display", "width": 1920, "height": 1080, "refreshRate": 143.85600,
             "x": 2560, "y": 0, "scale": 1.0},
        ]

    @preview.Slot(str)
    def log(self, text):
        if text.startswith("exec ") and "display-watchdog.py" in text:
            cmd = json.loads(text[5:])
            if cmd[2] == "arm":
                self.armed[cmd[3]] = cmd[5:]
        self.ran.append(text)

    def watchdog_fires(self):
        """As the detached watchdog does when nobody kept the change."""
        for token, rules in list(self.armed.items()):
            self.batch(rules)
            del self.armed[token]

    def batch(self, rules):
        for r in rules:
            name, mode, pos, scale = [x.strip() for x in r.split(",")]
            m = next(m for m in self.mons if m["name"] == name)
            x, y = pos.split("x")
            m.update(x=int(x), y=int(y), scale=float(scale))

    @Slot("QVariant", result="QVariantMap")
    def run(self, cmd):
        cmd = cmd.toVariant() if hasattr(cmd, "toVariant") else cmd
        line = " ".join(str(c) for c in cmd)
        self.ran.append(line)
        if cmd[:3] == ["hyprctl", "monitors", "-j"]:
            return {"stdout": json.dumps(self.mons), "stderr": "", "code": 0}
        if cmd[:2] == ["hyprctl", "--batch"]:
            for r in cmd[2].split(" ; "):
                name, mode, pos, scale = [x.strip() for x in r[len("keyword monitor "):].split(",")]
                m = next(m for m in self.mons if m["name"] == name)
                x, y = pos.split("x")
                m.update(x=int(x), y=int(y), scale=float(scale) if not self.refuse else m["scale"])
            return {"stdout": "ok", "stderr": "", "code": 0}
        if any(str(c).endswith("display-watchdog.py") for c in cmd):
            action, token = cmd[2], cmd[3]
            if action == "revert" and token in self.armed:
                self.batch(self.armed.pop(token))
            elif action == "keep":
                self.armed.pop(token, None)
            return {"stdout": '{"ok": true}', "stderr": "", "code": 0}
        if any(str(c).endswith("write-file.py") for c in cmd):
            return {"stdout": "", "stderr": "Read-only file system" if self.write_fails else "", "code": 1 if self.write_fails else 0}
        return {"stdout": "", "stderr": "", "code": 1 if cmd[0] in ("cat", "sh") else 0}


class Displays(unittest.TestCase):
    def load(self, refuse=False, write_fails=False):
        home = Path(tempfile.mkdtemp())
        self.hypr = Hypr({"HOME": str(home), "XDG_CONFIG_HOME": str(home / ".config")}, refuse, write_fails)
        self.view = QQuickView()
        self.view.engine().addImportPath(str(ROOT / "tools/preview/qml"))
        self.view.engine().rootContext().setContextProperty("__preview", self.hypr)
        c = QQmlComponent(self.view.engine())
        c.setData(b'import QtQuick\nimport "../apps/settings"\nimport "../apps/settings/panes"\n'
                  b'Item { width: 700; height: 600; Sys { id: s } DisplaysPane { objectName: "pane"; sys: s; width: 640 } }',
                  QUrl.fromLocalFile(str(ROOT / "tests" / "DisplaysFixture.qml")))
        self.assertEqual(c.status(), QQmlComponent.Ready, "\n".join(e.toString() for e in c.errors()))
        self.c = c
        self.root = c.create()
        self.pane = self.root.findChild(QObject, "pane")
        QTest.qWait(150)

    def eval(self, expr):
        v = QQmlExpression(self.view.engine().rootContext(), self.pane, expr).evaluate()[0]
        return v.toVariant() if hasattr(v, "toVariant") else v

    def scale(self, name, s):
        self.eval(f'setScale(monitors.find((m) => m.name === "{name}"), {s})')
        QTest.qWait(200)

    def mon(self, name):
        return next(m for m in self.hypr.mons if m["name"] == name)

    def test_the_layout_survives(self):
        self.load()
        self.scale("eDP-1", 2)
        self.assertEqual((self.mon("eDP-1")["x"], self.mon("eDP-1")["scale"]), (0, 2.0))
        self.assertEqual(self.mon("DP-1")["x"], 1280, "the display to the right follows the new edge")
        batch = next(l for l in self.hypr.ran if l.startswith("hyprctl --batch"))
        self.assertIn("eDP-1, 2560x1600@59.999, 0x0, 2", batch, "the exact mode, and its place")
        self.assertTrue(self.eval("pending.length > 0"), "asks to keep it")
        self.assertFalse(any("write-file.py" in l for l in self.hypr.ran), "nothing saved yet")
        self.assertEqual(len(self.hypr.armed), 1, "a watchdog of its own is armed")
        self.eval("keep()")
        QTest.qWait(200)
        self.assertTrue(any("write-file.py" in l and l.endswith("displays.conf") for l in self.hypr.ran))
        self.assertEqual(self.hypr.armed, {}, "kept: the watchdog stands down once it's saved")
        self.assertEqual(self.mon("eDP-1")["scale"], 2.0)

    def test_no_answer_goes_back(self):
        self.load()
        self.scale("eDP-1", 1.25)
        self.assertEqual(self.mon("eDP-1")["scale"], 1.25)
        self.pane.setProperty("countdown", 1)
        QTest.qWait(1400)
        self.assertEqual((self.mon("eDP-1")["scale"], self.mon("DP-1")["x"]), (1.0, 2560))
        self.assertFalse(self.eval("pending.length > 0"))
        self.assertFalse(any("write-file.py" in l for l in self.hypr.ran))

    def test_closing_settings_still_goes_back(self):
        self.load()
        self.scale("eDP-1", 2)
        self.root.deleteLater()                  # Settings closed mid-trial
        QTest.qWait(100)
        self.hypr.watchdog_fires()
        self.assertEqual((self.mon("eDP-1")["scale"], self.mon("DP-1")["x"]), (1.0, 2560))

    def test_a_keep_that_cant_be_saved_goes_back(self):
        self.load(write_fails=True)
        self.scale("eDP-1", 2)
        self.eval("keep()")
        QTest.qWait(300)
        self.assertEqual(self.mon("eDP-1")["scale"], 1.0, "not left live but unsaved")
        self.assertIn("couldn't be saved", self.eval("scaleError"))

    def test_only_whole_pixel_scales(self):
        self.load()
        self.assertTrue(self.eval('fits(monitors[0], 1.6)'))
        self.assertFalse(self.eval('fits({width: 1366, height: 768}, 1.25)'))

    def test_a_refused_scale_is_put_back(self):
        self.load(refuse=True)
        self.scale("eDP-1", 2)
        self.assertIn("couldn't be used", self.eval("scaleError"))
        self.assertEqual(self.mon("DP-1")["x"], 2560, "the other display is back where it was")
        self.assertFalse(self.eval("pending.length > 0"))


class Watchdog(unittest.TestCase):
    """display-watchdog.py on its own, with hyprctl stood in for."""
    def setUp(self):
        import subprocess
        self.sp = subprocess
        self.tmp = Path(tempfile.mkdtemp())
        (self.tmp / "bin").mkdir()
        (self.tmp / "bin/hyprctl").write_text('#!/bin/sh\necho "$*" >> "$CALLS"\necho ok\n')
        (self.tmp / "bin/hyprctl").chmod(0o755)
        self.env = {**os.environ, "PATH": f"{self.tmp/'bin'}:{os.environ['PATH']}", "CALLS": str(self.tmp / "calls"),
                    "XDG_RUNTIME_DIR": str(self.tmp)}

    def run_dog(self, *args, wait=True):
        cmd = [sys.executable, str(ROOT / "apps/settings/display-watchdog.py"), *args]
        return self.sp.run(cmd, env=self.env, capture_output=True, text=True) if wait else \
            self.sp.Popen(cmd, env=self.env, stdout=self.sp.PIPE, text=True)

    def calls(self):
        return (self.tmp / "calls").read_text() if (self.tmp / "calls").exists() else ""

    def test_goes_back_with_nobody_there(self):
        r = self.run_dog("arm", "t1", "0.5", "eDP-1, 2560x1600@59.999, 0x0, 1")
        self.assertIn("reverted", r.stdout)
        self.assertIn("keyword monitor eDP-1, 2560x1600@59.999, 0x0, 1", self.calls())

    def test_kept_means_nothing_happens(self):
        p = self.run_dog("arm", "t2", "2", "eDP-1, 2560x1600@59.999, 0x0, 1", wait=False)
        import time
        time.sleep(0.4)
        self.run_dog("keep", "t2")
        out, _ = p.communicate(timeout=10)
        self.assertIn("kept", out)
        self.assertEqual(self.calls(), "")

    def test_revert_now(self):
        p = self.run_dog("arm", "t3", "5", "eDP-1, 2560x1600@59.999, 0x0, 1", wait=False)
        import time
        time.sleep(0.4)
        self.run_dog("revert", "t3")
        p.communicate(timeout=10)
        self.assertEqual(self.calls().count("keyword monitor"), 1, "put back once")


if __name__ == "__main__":
    unittest.main(verbosity=2)
