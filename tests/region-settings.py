#!/usr/bin/env python3
"""Language & Region and Finish Setting Up (apps/settings/region.py, with
LanguagePane.qml and FinishSetupPane.qml): the language and the region's
formats are separate, so an English (US) system whose owner chose Swiss
formats in Setup shows Swiss formats; choosing formats in Settings writes
them for new sessions and into region.json without losing the rest; what
Setup put off is listed until it's actually finished, a refusal says so
and can be tried again, and the list goes once it's empty."""
import os
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from PySide6.QtCore import QObject, QUrl, Slot
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlExpression
from PySide6.QtQuick import QQuickItem, QQuickView
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/preview"))
import preview
APP = QGuiApplication([])
TOOL = ROOT / "apps/settings/region.py"
SAVE = ROOT / "apps/setup/save-preferences.py"


def tool(env, *args):
    p = subprocess.run([sys.executable, str(TOOL), *args], env={**os.environ, **env}, capture_output=True, text=True)
    return json.loads(p.stdout), p.returncode


class Home(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.conf = Path(self.tmp.name)
        self.env = {"XDG_CONFIG_HOME": str(self.conf)}

    def tearDown(self):
        self.tmp.cleanup()

    def setup_assistant(self, deferred, formats="de_CH", zone="Europe/Zurich"):
        """As Hello finishes: choices saved, some put off, setup done."""
        data = {"layout": "ch", "variant": "fr", "look": "light", "zone": zone, "formats": formats,
                "region": "Switzerland", "deferred": deferred}
        subprocess.run([sys.executable, str(SAVE), "--done"], input=json.dumps(data), text=True, check=True,
                       env={**os.environ, **self.env})


class Backend(Home):
    def test_status_reads_what_setup_saved(self):
        self.setup_assistant(["timezone", "location"])
        r, _ = tool(self.env, "status")
        self.assertEqual((r["region"], r["zone"], r["formats"]), ("Switzerland", "Europe/Zurich", "de_CH"))
        self.assertEqual(r["deferred"], ["location", "timezone"])

    def test_set_formats_merges_and_resolves(self):
        self.setup_assistant(["formats", "timezone"])
        r, code = tool(self.env, "set-formats", "fr_CH")
        self.assertEqual(code, 0, r)
        saved = json.loads((self.conf / "golden-gate/region.json").read_text())
        self.assertEqual(saved, {"region": "Switzerland", "zone": "Europe/Zurich", "formats": "fr_CH"}, "the rest kept")
        self.assertIn("LC_TIME=fr_CH.UTF-8", (self.conf / "environment.d/90-golden-formats.conf").read_text())
        self.assertEqual(tool(self.env, "status")[0]["deferred"], ["timezone"])

    def test_the_list_goes_once_empty(self):
        self.setup_assistant(["timezone"])
        tool(self.env, "set-zone", "Europe/Zurich")
        self.assertFalse((self.conf / "golden-gate/setup-deferred.json").exists())
        self.assertEqual(tool(self.env, "status")[0]["deferred"], [])

    def test_refused_input(self):
        self.assertNotEqual(tool(self.env, "set-formats", "../etc")[1], 0)
        self.assertNotEqual(tool(self.env, "set-zone", "a b")[1], 0)
        self.assertNotEqual(tool(self.env, "resolve", "account")[1], 0)

    def test_a_damaged_record_is_left(self):
        (self.conf / "golden-gate").mkdir(parents=True)
        (self.conf / "golden-gate/region.json").write_text("{bad")
        r, code = tool(self.env, "set-formats", "fr_CH")
        self.assertNotEqual(code, 0)
        self.assertEqual((self.conf / "golden-gate/region.json").read_text(), "{bad")


class Stand(preview.Preview):
    """region.py runs for real in this home; timedatectl, gsettings and the
    administrator helper answer as told."""
    def __init__(self, env, refuse=()):
        super().__init__(env, str(ROOT / "apps"), "'default'")
        self.home_env = env
        self.refuse = set(refuse)
        self.ran = []

    @Slot("QVariant", result="QVariantMap")
    def run(self, cmd):
        cmd = [str(c) for c in (cmd.toVariant() if hasattr(cmd, "toVariant") else cmd)]
        line = " ".join(cmd)
        self.ran.append(line)
        if "region.py" in line:
            p = subprocess.run([sys.executable, *cmd[1:]], env={**os.environ, **self.home_env}, capture_output=True, text=True)
            return {"stdout": p.stdout, "stderr": p.stderr, "code": p.returncode}
        for name in ("timedatectl", "gsettings", "account-call.sh"):
            if name in line and name in self.refuse:
                return {"stdout": '{"ok": false, "zone": null, "formats": "Authorization was refused."}' if name == "account-call.sh"
                        else "Access denied", "stderr": "", "code": 1}
        if "account-call.sh" in line:
            return {"stdout": '{"ok": true, "zone": null, "formats": null}', "stderr": "", "code": 0}
        if "locale -a" in line:
            return {"stdout": "C.utf8\nen_US.utf8\nde_CH.utf8\nfr_CH.utf8\n", "stderr": "", "code": 0}
        if "localectl status" in line:
            return {"stdout": "en_US.UTF-8\n", "stderr": "", "code": 0}
        return {"stdout": "", "stderr": "", "code": 0}


class Panes(Home):
    def load(self, pane, refuse=()):
        self.stand = Stand({"HOME": self.tmp.name, **self.env}, refuse)
        self.view = QQuickView()
        self.view.engine().addImportPath(str(ROOT / "tools/preview/qml"))
        self.view.engine().rootContext().setContextProperty("__preview", self.stand)
        c = QQmlComponent(self.view.engine())
        c.setData(('import QtQuick\nimport "../apps/settings"\nimport "../apps/settings/panes"\n'
                   'Item { width: 720; height: 900\n'
                   '  Item { id: nav; property Item overlay: parent; property string opened: ""; function open(id) { opened = id } }\n'
                   '  Sys { id: s }\n'
                   f'  {pane} {{ objectName: "pane"; sys: s; nav: nav; width: 680; height: 880 }} }}').encode(),
                  QUrl.fromLocalFile(str(ROOT / "tests" / "RegionFixture.qml")))
        self.assertEqual(c.status(), QQmlComponent.Ready, "\n".join(e.toString() for e in c.errors()))
        self.c = c
        self.root = c.create()
        self.pane = self.root.findChild(QObject, "pane")
        QTest.qWait(400)

    def eval(self, expr):
        v = QQmlExpression(self.view.engine().rootContext(), self.pane, expr).evaluate()[0]
        return v.toVariant() if hasattr(v, "toVariant") else v

    def item(self, name):
        def walk(i):
            if i.objectName() == name:
                return i
            for k in i.childItems():
                f = walk(k)
                if f:
                    return f
        return walk(self.pane)

    def test_english_language_swiss_region(self):
        self.setup_assistant([])
        self.load("LanguagePane")
        self.assertEqual(self.eval("lang"), "en_US.UTF-8")
        self.assertEqual(self.eval("formats"), "de_CH", "the saved formats, not the language's")
        self.assertEqual(self.item("regionMeasurement").property("text"), "Metric")
        self.assertEqual(self.item("regionDate").property("text"), "31.01.26")

    def test_choosing_formats_in_settings(self):
        self.setup_assistant([])
        self.load("LanguagePane")
        self.eval('setFormats("fr_CH")')
        QTest.qWait(400)
        self.assertEqual(self.eval("formats"), "fr_CH")
        self.assertIn("LC_MEASUREMENT=fr_CH.UTF-8", (self.conf / "environment.d/90-golden-formats.conf").read_text())
        self.assertIn("next sign in", self.eval("message"))

    def test_put_off_then_finished_later(self):
        self.setup_assistant(["timezone", "formats", "location"])
        self.load("FinishSetupPane", refuse=("timedatectl",))
        self.assertEqual(self.eval("items"), ["formats", "location", "timezone"])
        self.eval('finishItem("timezone")')
        QTest.qWait(300)
        self.assertIn("Access denied", self.eval('errors["timezone"]'), "a refusal says why")
        self.assertEqual(self.item("finishButton-timezone").property("text"), "Try Again")
        self.assertIn("timezone", self.eval("items"), "still listed")
        self.stand.refuse = set()
        for item in ("timezone", "formats", "location"):
            self.eval(f'finishItem("{item}")')
            QTest.qWait(400)
        self.assertIn("timedatectl set-timezone Europe/Zurich", "\n".join(self.stand.ran))
        self.assertTrue(any("account-call.sh" in l and '"formats":"de_CH"' in l for l in self.stand.ran))
        self.assertEqual(self.eval("items"), [])
        self.assertFalse((self.conf / "golden-gate/setup-deferred.json").exists())
        self.assertTrue(self.item("finishSetupDone").property("visible"))

    def test_nothing_put_off(self):
        self.setup_assistant([])
        self.load("FinishSetupPane")
        self.assertEqual(self.eval("items"), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
