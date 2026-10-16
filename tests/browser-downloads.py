#!/usr/bin/env python3
"""Load the production Web window and check terminal download states.

Only about:blank and a temporary profile are used. No user data or network
downloads are accessed. Chromium's root test fixture needs sandbox disabled;
the production launcher still refuses root and leaves sandboxing enabled.
"""
import os
from pathlib import Path
import sys
import tempfile
import unittest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QTWEBENGINE_CHROMIUM_FLAGS", "--disable-gpu")
if os.geteuid() == 0:
    os.environ["QTWEBENGINE_DISABLE_SANDBOX"] = "1"
from PySide6.QtCore import QEvent, QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine, QQmlExpression, QQmlEngine
from PySide6.QtTest import QTest
from PySide6.QtWebEngineQuick import QtWebEngineQuick

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "apps/browser"))
from backend import BrowserBackend
QtWebEngineQuick.initialize()
APP = QGuiApplication([])


class Downloads(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        tmp = Path(self.tmp.name)
        self.backend = BrowserBackend(data_dir=tmp / "data", cache_dir=tmp / "cache", download_dir=tmp / "downloads")
        self.engine = QQmlApplicationEngine()
        self.engine.rootContext().setContextProperty("BrowserBackend", self.backend)
        self.engine.load(QUrl.fromLocalFile(str(ROOT / "apps/browser/Browser.qml")))
        self.assertTrue(self.engine.rootObjects())
        self.window = self.engine.rootObjects()[0]
        QTest.qWait(200)

    def eval(self, text):
        e = QQmlExpression(QQmlEngine.contextForObject(self.window), self.window, text)
        value = e.evaluate()[0]
        self.assertFalse(e.hasError(), e.error().toString())
        return value

    def tearDown(self):
        self.window.close()
        self.engine.deleteLater()
        APP.processEvents()
        APP.sendPostedEvents(None, QEvent.DeferredDelete)
        self.tmp.cleanup()

    def test_terminal_states_and_pause(self):
        for state, label in (("DownloadCompleted", "Completed"), ("DownloadCancelled", "Cancelled"), ("DownloadInterrupted", "Failed: Network disconnected")):
            result = self.eval('downloadLabel({state:WebEngineDownloadRequest.' + state + ',isFinished:true,interruptReasonString:"Network disconnected"})')
            self.assertEqual(result, label)
        self.assertEqual(self.eval('downloadLabel({state:WebEngineDownloadRequest.DownloadInProgress,isPaused:true})'), "Paused")
        self.assertEqual(self.eval('downloadLabel({state:WebEngineDownloadRequest.DownloadInProgress,isPaused:false,totalBytes:100,receivedBytes:25})'), "25%")


if __name__ == "__main__":
    unittest.main(verbosity=2)
