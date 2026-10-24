#!/usr/bin/env python3
"""A Wi-Fi password never goes on a command line (CS2-016).

Any account can read every process's argv (ps, /proc/PID/cmdline), so
Settings › Wi-Fi and Setup Assistant send the password to nmcli on stdin
(nmcli --ask). The production panes are loaded in the preview harness; every
command they start and everything they write to a program's stdin is recorded.
"""
import os
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
import json
from pathlib import Path
import sys
import tempfile
import unittest

from PySide6.QtCore import QObject, QUrl, Slot
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlExpression
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/preview"))
import preview  # noqa: E402
APP = QGuiApplication([])
PASSWORD = "correct horse $(battery) staple"


class Stand(preview.Preview):
    def __init__(self, home):
        super().__init__({"HOME": home, "XDG_CONFIG_HOME": home + "/config"}, str(ROOT / "apps"), "'default'")
        self.commands, self.stdin = [], []

    @Slot(str)
    def log(self, text):
        if text.startswith("stdin "):
            self.stdin.append(json.loads(text[6:]))

    @Slot("QVariant", result="QVariantMap")
    def run(self, cmd):
        cmd = [str(c) for c in (cmd.toVariant() if hasattr(cmd, "toVariant") else cmd)]
        self.commands.append(cmd)
        if cmd[:3] == ["nmcli", "-t", "radio"]:
            return {"stdout": "enabled\n", "stderr": "", "code": 0}
        return {"stdout": "", "stderr": "", "code": 0}


class WifiPassword(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.stand = Stand(self.tmp.name)
        self.view = QQuickView()
        self.view.engine().addImportPath(str(ROOT / "tools/preview/qml"))
        self.view.engine().rootContext().setContextProperty("__preview", self.stand)

    def tearDown(self):
        self.tmp.cleanup()

    def load(self, source, fixture):
        c = QQmlComponent(self.view.engine())
        c.setData(source.encode(), QUrl.fromLocalFile(str(ROOT / "tests" / fixture)))
        self.assertEqual(c.status(), QQmlComponent.Ready, "\n".join(e.toString() for e in c.errors()))
        self.c = c
        self.root = c.create()
        self.pane = self.root.findChild(QObject, "pane")
        QTest.qWait(200)

    def call(self, expr):
        e = QQmlExpression(self.view.engine().rootContext(), self.pane, expr)
        e.evaluate()
        self.assertFalse(e.hasError(), e.error().toString())
        QTest.qWait(100)

    def check(self):
        joins = [c for c in self.stand.commands if "connect" in c]
        self.assertEqual(len(joins), 1, self.stand.commands)
        self.assertIn("--ask", joins[0], "nmcli asks for the password on stdin")
        self.assertEqual(joins[0][-1], "Home Network")
        for cmd in self.stand.commands:
            self.assertFalse(any(PASSWORD in a for a in cmd), f"the password is in argv: {cmd}")
            self.assertNotIn("password", cmd)
        sent = [s for s in self.stand.stdin if "connect" in s["command"]]
        self.assertEqual([s["data"] for s in sent], [PASSWORD + "\n"], "the password went to nmcli's stdin, once")

    def test_settings_wifi(self):
        self.load('import QtQuick\nimport "../apps/settings"\nimport "../apps/settings/panes"\n'
                  'Item { width: 720; height: 900\n'
                  '  Item { id: nav; property Item overlay: parent; property string opened: ""; function open(id) { opened = id } }\n'
                  '  Sys { id: s }\n'
                  '  WifiPane { objectName: "pane"; sys: s; nav: nav; width: 680; height: 880 } }', "WifiFixture.qml")
        self.call(f"join('Home Network', {json.dumps(PASSWORD)})")
        self.check()

    def test_open_network_needs_no_stdin(self):
        self.load('import QtQuick\nimport "../apps/settings"\nimport "../apps/settings/panes"\n'
                  'Item { width: 720; height: 900\n'
                  '  Item { id: nav; property Item overlay: parent; property string opened: ""; function open(id) { opened = id } }\n'
                  '  Sys { id: s }\n'
                  '  WifiPane { objectName: "pane"; sys: s; nav: nav; width: 680; height: 880 } }', "WifiFixture.qml")
        self.call("join('Cafe', '')")
        joins = [c for c in self.stand.commands if "connect" in c]
        self.assertEqual(joins, [["nmcli", "--wait", "30", "device", "wifi", "connect", "Cafe"]])

    def test_setup_assistant_wifi(self):
        self.load('import QtQuick\nimport "../apps/setup"\n'
                  'Item { width: 720; height: 900\n'
                  '  WifiStep { objectName: "pane"; width: 680; height: 880 } }', "SetupWifiFixture.qml")
        self.call(f"join({{ ssid: 'Home Network' }}, {json.dumps(PASSWORD)})")
        self.check()


if __name__ == "__main__":
    unittest.main()
