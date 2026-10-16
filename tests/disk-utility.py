#!/usr/bin/env python3
"""Disk Utility (apps/diskutility.qml) on tools/preview/fixtures/disks.json:
it opens on the system's volume, whose Erase, First Aid, Unmount and Eject
stay off; an external volume can be erased, unmounted and ejected; the Erase
sheet is filled in and runs the erase; What's Using Space measures a folder."""
import os
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
from pathlib import Path
import sys
import tempfile
import unittest

from PySide6.QtCore import QMetaObject, QObject, QUrl, Q_ARG
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/preview"))
import preview
APP = QGuiApplication([])


class DiskUtility(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp())
        env = {"HOME": str(self.home), "USER": "you", "XDG_CONFIG_HOME": str(self.home / ".config"),
               "XDG_RUNTIME_DIR": str(self.home), "GG_DISKS_FIXTURE": str(ROOT / "tools/preview/fixtures/disks.json")}
        self.view = QQuickView()
        self.fake = preview.Preview(env, str(ROOT / "apps"), "'default'")
        self.view.engine().addImportPath(str(ROOT / "tools/preview/qml"))
        self.view.engine().rootContext().setContextProperty("__preview", self.fake)
        component = QQmlComponent(self.view.engine())
        component.setData(b'import QtQuick\nItem { width: 1000; height: 640; Loader { source: "../apps/diskutility.qml" } }',
                          QUrl.fromLocalFile(str(ROOT / "tests" / "DiskUtilityFixture.qml")))
        self.assertEqual(component.status(), QQmlComponent.Ready, "\n".join(e.toString() for e in component.errors()))
        self.root = component.create()
        self.component = component
        self.du = None
        for _ in range(80):
            QTest.qWait(50)
            title = self.root.findChild(QObject, "duTitle")
            if title is not None and title.property("text"):
                self.du = self.find_du(title)
                break
        self.assertIsNotNone(self.du, "Disk Utility opened on a volume")

    @staticmethod
    def find_du(item):
        while item is not None and item.property("formats") is None:
            item = item.parentItem() if hasattr(item, "parentItem") else item.parent()
        return item

    def tearDown(self):
        self.root.deleteLater()
        APP.processEvents()

    def value(self, name):
        v = self.du.property(name)
        return v.toVariant() if hasattr(v, "toVariant") else v

    def obj(self, name):
        return self.root.findChild(QObject, name)

    def call(self, name, *args):
        QMetaObject.invokeMethod(self.du, name, *[Q_ARG("QVariant", a) for a in args])

    def wait_for(self, check, ms=6000):
        for _ in range(ms // 50):
            if check():
                return True
            QTest.qWait(50)
        return check()

    def choose(self, name):
        for disk in self.value("disks"):
            for v in disk["volumes"]:
                if v["name"] == name:
                    self.du.setProperty("selected", "volume:" + (v["device"] or v["mountpoint"]))
                    QTest.qWait(50)
                    return v
        self.fail(name + " not found")

    def test_opens_on_the_system_which_is_left_alone(self):
        self.assertEqual(self.obj("duTitle").property("text"), "CitronOS")
        for action in ("duErase", "duFirstAid", "duMount"):
            self.assertFalse(self.obj(action).property("on"), action + " is off for the running system")
        facts = dict(self.obj("duFacts").property("rows").toVariant())
        self.assertEqual(facts["Mount Point"], "/")
        self.assertEqual(facts["Available"], "320 GB")

    def test_an_external_volume(self):
        self.choose("BACKUP")
        self.assertEqual(self.obj("duTitle").property("text"), "BACKUP")
        for action in ("duErase", "duFirstAid", "duMount", "duEject"):
            self.assertTrue(self.obj(action).property("on"), action)
        self.assertEqual(self.obj("duMount").property("label"), "Unmount")
        self.choose("Windows")
        self.assertEqual(self.obj("duMount").property("label"), "Mount", "Windows isn't mounted")
        self.assertFalse(self.obj("duEject").property("on"), "an internal disk isn't ejected")

    def test_erase(self):
        self.choose("BACKUP")
        self.call("ask", "erase")
        QTest.qWait(50)
        self.assertTrue(self.obj("duEraseSheet").property("visible"))
        self.assertEqual(self.obj("duEraseName").property("text"), "BACKUP")
        self.assertEqual(self.obj("duEraseFormat").property("current"), 0, "ExFAT, as it was")
        self.obj("duEraseConfirm").clicked.emit()
        self.assertFalse(self.obj("duEraseSheet").property("visible"))
        # The disks are a sample: the erase is asked for, refused, and says why.
        self.assertTrue(self.wait_for(lambda: not self.value("busy") and self.value("message")))
        self.assertTrue(self.value("messageBad"))
        self.assertIn("sample disks", self.value("message"))

    def test_whats_using_space(self):
        tmp = Path(tempfile.mkdtemp())
        (tmp / "Movies").mkdir()
        (tmp / "Movies/film").write_bytes(b"x" * 300_000)
        (tmp / "Notes").mkdir()
        (tmp / "Notes/n").write_bytes(b"x" * 2_000)
        self.call("run", "largest", [str(tmp)], "Measuring…")
        self.assertTrue(self.wait_for(lambda: self.value("largest") is not None))
        self.assertEqual([i["name"] for i in self.value("largest")["items"]], ["Movies", "Notes"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
