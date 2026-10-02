#!/usr/bin/env python3
"""Exercise Golden Gate Web's real Qt Quick / Chromium browser against localhost."""
import os
os.environ.setdefault("QT_QPA_PLATFORM", "xcb")
os.environ.setdefault("QTWEBENGINE_CHROMIUM_FLAGS", "--disable-gpu")
if os.geteuid() == 0 and os.environ.get("GG_TEST_UNSANDBOXED") == "1":
    os.environ["QTWEBENGINE_CHROMIUM_FLAGS"] += " --no-sandbox"

import http.server
from pathlib import Path
import sys
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
BROWSER = ROOT / "apps/browser"
sys.path.insert(0, str(BROWSER))

from PySide6.QtCore import QCoreApplication, QEvent
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtTest import QTest
from PySide6.QtWebEngineQuick import QtWebEngineQuick

QtWebEngineQuick.initialize()
APP = QGuiApplication([])
APP.setApplicationName("GoldenGateWebTest")

from backend import BrowserBackend


class Fixture(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        page = (
            f"<title>Fixture {self.path}</title>"
            '<article><h1>Reader Title</h1><p>Local browser test article.</p></article>'
            '<a href="/second">Second page</a>'
        )
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.end_headers()
        try:
            self.wfile.write(page.encode())
        except BrokenPipeError:
            pass

    def log_message(self, *_):
        pass


SERVER = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Fixture)
threading.Thread(target=SERVER.serve_forever, daemon=True).start()
BASE = f"http://127.0.0.1:{SERVER.server_port}"


def until(predicate, timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        APP.processEvents()
        if predicate():
            return
        QTest.qWait(25)
    raise AssertionError("Timed out waiting for browser")


class QmlBrowser(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.backend = BrowserBackend(
            data_dir=base / "data",
            cache_dir=base / "cache",
            download_dir=base / "downloads",
        )
        self.engine = QQmlApplicationEngine()
        self.engine.rootContext().setContextProperty("BrowserBackend", self.backend)
        self.engine.load((BROWSER / "Browser.qml").as_uri())
        self.assertTrue(self.engine.rootObjects(), "Browser.qml failed to create its window")
        self.window = self.engine.rootObjects()[0]
        until(lambda: int(self.window.property("tabCount")) >= 1)

    def tearDown(self):
        self.window.close()
        self.engine.deleteLater()
        QCoreApplication.sendPostedEvents(None, QEvent.DeferredDelete)
        for _ in range(12):
            APP.processEvents()
            QTest.qWait(30)
        self.tmp.cleanup()

    def test_start_page_and_safari_chrome(self):
        self.assertEqual(self.window.property("currentUrl"), "about:blank")
        self.assertEqual(int(self.window.property("tabCount")), 1)
        qml = (BROWSER / "Browser.qml").read_text()
        for needle in [
            "Search or enter website name",
            "Tab Layout",
            "Reading List",
            "Recently Closed",
            "Page Menu",
            "Web Settings",
            "Reader",
        ]:
            self.assertIn(needle, qml)

    def test_real_webengine_navigation(self):
        view = self.window.property("currentView")
        self.assertIsNotNone(view)
        view.setProperty("url", BASE + "/first")
        until(lambda: view.property("title") == "Fixture /first")
        self.assertEqual(view.property("url").toString(), BASE + "/first")
        until(lambda: bool(self.backend.store.data["history"]))
        self.assertEqual(self.backend.store.data["history"][0]["url"], BASE + "/first")

    def test_multiple_restored_tabs_have_web_views(self):
        self.window.close()
        self.engine.deleteLater()
        QCoreApplication.sendPostedEvents(None, QEvent.DeferredDelete)
        APP.processEvents()

        base = Path(self.tmp.name)
        self.backend = BrowserBackend(
            launch_values=[BASE + "/one", BASE + "/two"],
            data_dir=base / "data2",
            cache_dir=base / "cache2",
            download_dir=base / "downloads2",
        )
        self.engine = QQmlApplicationEngine()
        self.engine.rootContext().setContextProperty("BrowserBackend", self.backend)
        self.engine.load((BROWSER / "Browser.qml").as_uri())
        self.window = self.engine.rootObjects()[0]
        until(lambda: int(self.window.property("tabCount")) == 2)
        self.assertEqual(int(self.window.property("tabCount")), 2)

    def test_private_state_stays_ephemeral(self):
        base = Path(self.tmp.name) / "private-check"
        private = BrowserBackend(
            private=True,
            data_dir=base / "data",
            cache_dir=base / "cache",
            download_dir=base / "downloads",
        )
        private.visit(BASE + "/private", "Private")
        private.saveTabs('["https://example.com"]')
        self.assertFalse((base / "data/private-state.json").exists())
        self.assertFalse(private.store.data["history"])

    def test_backend_search_and_collections(self):
        self.backend.addBookmark("https://example.com", "Example")
        self.backend.addReadingList("https://example.org/read", "Read This")
        suggestions = self.backend.suggestions("exam", "[]")
        self.assertIn("Example", suggestions)
        self.assertIn("example.com", suggestions)
        start = self.backend.startPageJson()
        self.assertIn("favorites", start)
        self.assertIn("readingList", start)

    def test_visual_preview(self):
        QTest.qWait(250)
        out = ROOT / "out/browser"
        out.mkdir(parents=True, exist_ok=True)
        image = self.window.grabWindow()
        self.assertFalse(image.isNull())
        self.assertTrue(image.save(str(out / "web-qml-start.png")))
        self.window.resize(760, 560)
        QTest.qWait(180)
        image = self.window.grabWindow()
        self.assertTrue(image.save(str(out / "web-qml-compact.png")))


if __name__ == "__main__":
    try:
        unittest.main(verbosity=2)
    finally:
        SERVER.shutdown()
