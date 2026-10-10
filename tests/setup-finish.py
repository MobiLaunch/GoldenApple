#!/usr/bin/env python3
"""Hello's last step (apps/setup.qml) waits for each part of finishing: your
choices saved, the time zone and region formats applied (one authorized
step), Location Services set, and only then setup-done. A part that fails
stops there with the reason, and Get Started tries it again or Set Up Later
puts it off (listed for later) and finishes. Commands are answered by a
stand-in; nothing is changed."""
import os
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
import json
from pathlib import Path
import sys
import tempfile
import unittest

from PySide6.QtCore import QMetaObject, QObject, QUrl, Q_ARG, Slot
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/preview"))
import preview
APP = QGuiApplication([])


class Stand(preview.Preview):
    def __init__(self, env, answers):
        super().__init__(env, str(ROOT / "apps"), "'default'")
        self.answers = answers
        self.ran = []

    @Slot("QVariant", result="QVariantMap")
    def run(self, cmd):
        cmd = cmd.toVariant() if hasattr(cmd, "toVariant") else cmd
        line = " ".join(str(c) for c in cmd)
        for key, answer in self.answers.items():
            if key in line:
                self.ran.append(key + (" --done" if "--done" in line else ""))
                return {"stdout": answer[0], "stderr": "", "code": answer[1]}
        return {"stdout": "", "stderr": "", "code": 1 if "test" in cmd[:1] else 0}


class Finishing(unittest.TestCase):
    def load(self, system=('{"ok":true,"zone":null,"formats":null}', 0), location=("", 0), step="9", extra=None):
        home = Path(tempfile.mkdtemp())
        env = {"HOME": str(home), "USER": "golden", "XDG_CONFIG_HOME": str(home / ".config"),
               "XDG_RUNTIME_DIR": str(home), "GG_SETUP_STEP": step}
        self.stand = Stand(env, {"save-preferences.py": ("", 0), "account-call.sh": system,
                                 "org.gnome.system.location": location, **(extra or {})})
        self.view = QQuickView()
        self.view.engine().addImportPath(str(ROOT / "tools/preview/qml"))
        self.view.engine().rootContext().setContextProperty("__preview", self.stand)
        component = QQmlComponent(self.view.engine())
        component.setData(b'import QtQuick\nItem { width: 1280; height: 800; Loader { source: "../apps/setup.qml" } }',
                          QUrl.fromLocalFile(str(ROOT / "tests" / "SetupFixture.qml")))
        self.assertEqual(component.status(), QQmlComponent.Ready, "\n".join(e.toString() for e in component.errors()))
        self.root = component.create()
        self.component = component
        self.stage = None
        for _ in range(60):
            QTest.qWait(50)
            self.stage = next((o for o in self.root.findChildren(QObject) if o.property("chain") is not None), None)
            if self.stage is not None:
                break
        self.assertIsNotNone(self.stage, "Hello loaded")
        QTest.qWait(100)
        self.stand.ran.clear()

    def tearDown(self):
        self.root.deleteLater()
        APP.processEvents()

    def value(self, name):
        v = self.stage.property(name)
        return v.toVariant() if hasattr(v, "toVariant") else v

    def call(self, name, *args):
        QMetaObject.invokeMethod(self.stage, name, *[Q_ARG("QVariant", a) for a in args])
        QTest.qWait(150)

    def test_everything_applied_then_done(self):
        self.load()
        self.call("finish", False)
        self.assertEqual(self.stand.ran, ["save-preferences.py", "account-call.sh", "org.gnome.system.location",
                                          "save-preferences.py --done"], "done comes last")
        self.assertEqual(self.value("finishError"), "")
        self.assertEqual(self.value("preferences")["zone"], self.value("zone"), "the time zone is saved with the rest")

    def test_a_failure_stops_before_done(self):
        self.load(system=('{"ok":false,"zone":"The time zone couldn\'t be set (timedatectl failed).","formats":""}', 0))
        self.call("finish", False)
        self.assertNotIn("save-preferences.py --done", self.stand.ran)
        self.assertFalse(self.value("finishing"))
        self.assertIn("timedatectl failed", self.value("finishError"))
        self.assertEqual(self.value("deferrable"), ["timezone"])
        # Set Up Later: the rest goes on, and the time zone is listed for later.
        self.stand.ran.clear()
        self.call("deferAndContinue")
        self.assertEqual(self.stand.ran, ["org.gnome.system.location", "save-preferences.py --done"])
        self.assertEqual(self.value("deferred"), ["timezone"])

    def test_refused_authorization_can_be_retried(self):
        self.load(system=("", 126))
        self.call("finish", False)
        self.assertIn("authorization", self.value("finishError"))
        self.assertEqual(sorted(self.value("deferrable")), ["formats", "timezone"])
        self.stand.answers["account-call.sh"] = ('{"ok":true,"zone":null,"formats":null}', 0)
        self.stand.ran.clear()
        self.call("finish", False)
        self.assertEqual(self.stand.ran, ["account-call.sh", "org.gnome.system.location", "save-preferences.py --done"],
                         "Get Started tries again from where it stopped")
        self.assertEqual(self.value("deferred"), [])

    def test_location_failure(self):
        self.load(location=("", 1))
        self.call("finish", False)
        self.assertIn("Location Services", self.value("finishError"))
        self.assertEqual(self.value("deferrable"), ["location"])
        self.assertNotIn("save-preferences.py --done", self.stand.ran)


    def texts(self):
        return [o.property("text") for o in self.root.findChildren(QObject)
                if o.metaObject().className().startswith("QQuickText") and o.property("text") and o.property("visible")]

    def test_live_session_offers_try_or_install(self):
        self.load(step="1")
        QTest.qWait(200)
        self.assertIn("Try or Install CitronOS", self.texts(), "no account is made on the USB")
        self.assertNotIn("Create Your Local Account", self.texts())

    def test_install_hands_the_screen_to_the_installer(self):
        self.load(step="1", extra={"gg-install": ("", 0)})
        QTest.qWait(200)
        win = next(o for o in self.root.findChildren(QObject) if o.property("exclusionMode") is not None)
        self.assertTrue(win.property("visible"))
        self.call("startInstaller")
        self.assertIn("gg-install", " ".join(self.stand.ran))
        # The stand-in installer has been closed again: Hello is back on Try or Install.
        self.assertTrue(win.property("visible"))
        self.assertEqual(self.value("step"), 1, "back where it was, not moved on")
        self.assertEqual(self.value("installError"), "")

    def test_hello_steps_aside_while_installing(self):
        self.load(step="1")
        win = next(o for o in self.root.findChildren(QObject) if o.property("exclusionMode") is not None)
        self.stage.setProperty("installing", True)
        QTest.qWait(50)
        self.assertFalse(win.property("visible"), "the installer isn't behind Hello")
        self.stage.setProperty("installing", False)
        QTest.qWait(50)
        self.assertTrue(win.property("visible"))

    def test_installer_that_wont_open(self):
        self.load(step="1", extra={"gg-install": ("", 1)})
        self.call("startInstaller")
        self.assertIn("couldn't be opened", self.value("installError"))
        shown = next(o for o in self.root.findChildren(QObject) if o.objectName() == "helloInstallError")
        self.assertIn("couldn't be opened", shown.property("text"), "said on the Try or Install page")
        self.assertEqual(self.value("step"), 1)

    def test_installed_account_skips_the_account_step(self):
        self.load(step="2", extra={"account-ready": ("", 0)})
        QTest.qWait(100)
        self.assertTrue(self.value("accountReady"))
        self.call("go", 1)
        QTest.qWait(1200)
        self.assertEqual(self.value("step"), 0, "back from Region skips Account")


if __name__ == "__main__":
    unittest.main(verbosity=2)
