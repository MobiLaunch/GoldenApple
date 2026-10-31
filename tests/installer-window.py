#!/usr/bin/env python3
"""The installer window (apps/installer.qml) as the helper's events drive it:
an error before the disk is touched goes back to the confirmation page; an
error after "erasing" goes to its own Didn't Finish page (stage, error, log)
with the erase confirmation cleared, and Start Over means choosing and
confirming the disk again; while installing, closing is refused."""
import json
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


class InstallerWindow(unittest.TestCase):
    def setUp(self):
        home = Path(tempfile.mkdtemp())
        env = {"HOME": str(home), "USER": "you", "XDG_CONFIG_HOME": str(home / ".config"), "XDG_RUNTIME_DIR": str(home)}
        self.view = QQuickView()
        self.fake = preview.Preview(env, str(ROOT / "apps"), "'default'")
        self.view.engine().addImportPath(str(ROOT / "tools/preview/qml"))
        self.view.engine().rootContext().setContextProperty("__preview", self.fake)
        component = QQmlComponent(self.view.engine())
        component.setData(b'import QtQuick\nItem { width: 780; height: 590; Loader { source: "../apps/installer.qml" } }',
                          QUrl.fromLocalFile(str(ROOT / "tests" / "InstallerFixture.qml")))
        self.assertEqual(component.status(), QQmlComponent.Ready, "\n".join(e.toString() for e in component.errors()))
        self.root = component.create()
        self.component = component
        self.stage = None
        for _ in range(60):
            QTest.qWait(50)
            self.stage = self.find_stage()
            if self.stage is not None:
                break
        self.assertIsNotNone(self.stage)
        # As if the preflight passed and the person filled everything in.
        for k, v in (("liveSession", True), ("preflightReady", True), ("username", "grace"),
                     ("password", "correct-horse"), ("passwordConfirm", "correct-horse"), ("eraseConfirmed", True)):
            self.stage.setProperty(k, v)
        self.stage.setProperty("disk", {"path": "/dev/sda", "model": "Samsung SSD", "size": 512e9, "identity": "Samsung SSD|S5|512"})

    def find_stage(self):
        item = self.root.findChild(QObject, "installerFailure")
        while item is not None and item.property("eraseConfirmed") is None:
            item = item.parentItem()
        return item

    def tearDown(self):
        self.root.deleteLater()
        APP.processEvents()

    def obj(self, name):
        return self.root.findChild(QObject, name)

    def consume(self, event):
        QMetaObject.invokeMethod(self.stage, "consume", Q_ARG("QVariant", json.dumps(event)))
        QTest.qWait(20)

    def installing(self):
        self.stage.setProperty("installing", True)
        self.stage.setProperty("step", 4)

    def test_error_before_erasing(self):
        self.installing()
        self.consume({"event": "progress", "progress": 0.03, "message": "Preparing destination"})
        self.consume({"event": "error", "message": "The disk at /dev/sda isn't the one you chose.", "erased": False})
        self.assertEqual(self.stage.property("step"), 3)
        self.assertFalse(self.stage.property("installing"))

    def test_error_after_erasing(self):
        self.installing()
        self.consume({"event": "erasing", "device": "/dev/sda"})
        self.consume({"event": "error", "message": "mkfs.ext4 failed", "erased": True,
                      "stage": "Creating filesystems", "log": "/run/citronos-install.log"})
        self.assertEqual(self.stage.property("step"), 6)
        self.assertFalse(self.stage.property("eraseConfirmed"), "a retry asks again")
        self.assertTrue(self.obj("installerFailure").property("visible"))
        self.assertEqual(self.stage.property("failedStage"), "Creating filesystems")
        self.obj("installerStartOver").clicked.emit()
        QTest.qWait(20)
        self.assertEqual(self.stage.property("step"), 1, "back to choosing the disk")
        self.assertIsNone(self.stage.property("disk"))
        self.assertFalse(self.stage.property("erased"))

    def test_closing_while_installing_is_refused(self):
        self.installing()
        win = self.stage
        while win is not None and win.property("closeAction") is None:
            win = win.parentItem() if hasattr(win, "parentItem") and win.parentItem() else win.parent()
        self.assertIsNotNone(win)
        QMetaObject.invokeMethod(win, "closeWindow")
        QTest.qWait(20)
        self.assertTrue(self.stage.property("closeRefused"))
        self.assertTrue(self.obj("installerCloseRefused").property("visible"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
