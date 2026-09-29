#!/usr/bin/env python3
"""Exercise real Chromium tabs against a local-only HTTP fixture.
CI runs as a normal user with Chromium's sandbox; a root container needs the
explicit GG_TEST_UNSANDBOXED=1 opt-in. Production launchers never set this flag.
"""
import os
os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
os.environ.setdefault('QTWEBENGINE_CHROMIUM_FLAGS', '--disable-gpu')
if os.geteuid() == 0 and os.environ.get('GG_TEST_UNSANDBOXED') == '1':
    os.environ['QTWEBENGINE_CHROMIUM_FLAGS'] += ' --no-sandbox'
import http.server
from pathlib import Path
import sys
import tempfile
import threading
import time
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'apps/browser'))
from PySide6.QtWidgets import QApplication, QFileDialog
from PySide6.QtCore import QCoreApplication, QEvent, Qt
from PySide6.QtTest import QTest
from browser import Browser
from unittest.mock import patch

APP = QApplication([])
APP.setApplicationName('GoldenGateWebTest')
ERRORS=[]
def exception(kind, value, tb):
    ERRORS.append(str(value))
    sys.__excepthook__(kind, value, tb)
sys.excepthook=exception

class Fixture(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        page=f'<title>Fixture {self.path}</title><a href="/second">Second page</a><p>Local browser test</p>'
        self.send_response(200); self.send_header('Content-Type','text/html'); self.end_headers()
        try: self.wfile.write(page.encode())
        except BrokenPipeError: pass
    def log_message(self, *_): pass
SERVER=http.server.ThreadingHTTPServer(('127.0.0.1',0), Fixture)
threading.Thread(target=SERVER.serve_forever, daemon=True).start()
BASE=f'http://127.0.0.1:{SERVER.server_port}'

def until(predicate, timeout=12):
    deadline=time.monotonic()+timeout
    while time.monotonic()<deadline:
        APP.processEvents()
        if predicate(): return
        QTest.qWait(20)
    raise AssertionError('Timed out waiting for browser')

class NativeBrowser(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.browser=Browser(data_dir=self.tmp.name)
        self.browser.show()
        until(lambda: self.browser.current().title()=='Start Page')
    def tearDown(self):
        self.browser.close()
        self.browser.deleteLater()
        QCoreApplication.sendPostedEvents(None, QEvent.DeferredDelete)
        APP.processEvents()
        # WebEngine profile/cache writes can outlive the window by a few event
        # turns. Retry only the temporary-directory cleanup; a persistent leak
        # still fails the test instead of being ignored.
        cleanup_error = None
        for _ in range(20):
            try:
                self.tmp.cleanup()
                cleanup_error = None
                break
            except OSError as error:
                cleanup_error = error
                QCoreApplication.sendPostedEvents(None, QEvent.DeferredDelete)
                APP.processEvents()
                QTest.qWait(50)
        if cleanup_error is not None:
            raise cleanup_error
        self.assertFalse(ERRORS, str(ERRORS))
    def test_start_page_and_tab_close(self):
        b=self.browser
        b.new_tab(); self.assertEqual(len(b.views),2)
        b.close_tab(1); self.assertEqual(len(b.views),1)
        b.close_tab(0); self.assertEqual(len(b.views),1)
        until(lambda:b.current().title()=='Start Page')
        self.assertEqual(b.tabs.count(),b.tab_list.count())
    def test_navigation_history_and_bookmark(self):
        b=self.browser
        b.go(BASE+'/first'); until(lambda:b.current().title()=='Fixture /first')
        b.go(BASE+'/second'); until(lambda:b.current().title()=='Fixture /second')
        self.assertTrue(b.back.isEnabled())
        b.current().back(); until(lambda:b.current().title()=='Fixture /first')
        b.bookmark(); b.save()
        self.assertEqual(b.store.data['bookmarks'][0]['url'],BASE+'/first')
        self.assertTrue(b.store.data['history'])
    def test_address_rejection_and_crash_recovery(self):
        b=self.browser
        b.address.setText('javascript:alert(1)'); b.navigate()
        self.assertIn('Only http',b.notice.text())
        b.renderer_failed(b.current(),139)
        self.assertIn('Ctrl+R',b.notice.text())
        self.assertEqual(len(b.views),1)
    def test_shortcuts_and_zoom(self):
        b=self.browser
        b.activateWindow(); QTest.qWait(50)
        QTest.keyClick(b,Qt.Key_T,Qt.ControlModifier)
        self.assertEqual(len(b.views),2)
        for _ in range(100): b.zoom(-.1)
        self.assertEqual(b.current().zoomFactor(),.25)
        for _ in range(100): b.zoom(.1)
        self.assertAlmostEqual(b.current().zoomFactor(),5)
    def test_private_profile(self):
        b=Browser(private=True,data_dir=self.tmp.name+'/private')
        self.assertTrue(b.profile.isOffTheRecord())
        b.save()
        self.assertFalse((Path(self.tmp.name)/'private/state.json').exists())
        b.close(); b.deleteLater()
        QCoreApplication.sendPostedEvents(None,QEvent.DeferredDelete)
    def test_download_cancel_does_not_accept(self):
        from unittest.mock import Mock
        request=Mock(); request.suggestedFileName.return_value='sample.txt'
        with patch.object(QFileDialog,'getSaveFileName',return_value=('', '')):
            self.browser.download(request)
        request.cancel.assert_called_once(); request.accept.assert_not_called()
    def test_restored_background_tabs_load_on_demand(self):
        b = self.browser
        view = b.add_tab(BASE + '/deferred', activate=False)
        self.assertEqual(view.pending_url, BASE + '/deferred')
        self.assertFalse(view.page().isLoading())
        b.save()
        self.assertIn(BASE + '/deferred', b.store.data['tabs'])
        b.select_tab(1)
        until(lambda: view.title() == 'Fixture /deferred')
        self.assertIsNone(view.pending_url)
    def test_visual(self):
        b=self.browser
        QTest.qWait(150)
        out=Path(__file__).resolve().parents[1]/'out/browser'
        out.mkdir(parents=True,exist_ok=True)
        self.assertTrue(b.grab().save(str(out/'web-light.png')))
        b.resize(680,480); QTest.qWait(250)
        self.assertTrue(b.grab().save(str(out/'web-compact.png')))

if __name__=='__main__':
    try: unittest.main(verbosity=2)
    finally: SERVER.shutdown()
