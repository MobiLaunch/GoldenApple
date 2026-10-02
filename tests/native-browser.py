#!/usr/bin/env python3
"""Exercise the production QML/Chromium browser path under Xvfb.

These tests intentionally launch apps/browser/browser.py itself. That catches
QML import/creation failures, Qt WebEngine initialization mistakes, profile
startup failures and single-instance handoff regressions that unit tests of the
state model cannot see.
"""
from __future__ import annotations

import http.server
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
BROWSER = ROOT / "apps/browser/browser.py"


class Fixture(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        page = (
            f"<title>Fixture {self.path}</title>"
            '<article><h1>Reader Test</h1><p>Golden Gate browser fixture content.</p></article>'
            '<a href="/second">Second page</a>'
        )
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
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


def browser_env(root: Path, exit_ms=1700):
    home = root / "home"
    data = root / "data"
    cache = root / "cache"
    downloads = root / "downloads"
    for path in (home, data, cache, downloads):
        path.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update({
        "HOME": str(home),
        "XDG_DATA_HOME": str(data),
        "XDG_CACHE_HOME": str(cache),
        "XDG_DOWNLOAD_DIR": str(downloads),
        "QT_QPA_PLATFORM": env.get("QT_QPA_PLATFORM", "xcb"),
        "QTWEBENGINE_CHROMIUM_FLAGS": (env.get("QTWEBENGINE_CHROMIUM_FLAGS", "") + " --disable-gpu").strip(),
        "GG_WEB_TEST_EXIT_MS": str(exit_ms),
    })
    return env


def state_files(root: Path):
    return list(root.rglob("state.json"))


class NativeQmlBrowser(unittest.TestCase):
    def run_browser(self, tmp: Path, *args, exit_ms=1700, timeout=12):
        env = browser_env(tmp, exit_ms)
        return subprocess.run(
            [sys.executable, str(BROWSER), *args],
            cwd=ROOT,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
        )

    def test_qml_chromium_starts_and_persists_session(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result = self.run_browser(root, BASE + "/first")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn("could not load its QML interface", result.stderr)
            self.assertNotIn("QQmlApplicationEngine failed", result.stderr)

            files = state_files(root)
            self.assertEqual(len(files), 1, [str(p) for p in files])
            state = json.loads(files[0].read_text())
            self.assertIn(BASE + "/first", state["tabs"])

    def test_private_window_is_off_record(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            result = self.run_browser(root, "--private", BASE + "/private")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(state_files(root), [])

    def test_named_profile_uses_isolated_state(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            personal = self.run_browser(root, BASE + "/personal")
            self.assertEqual(personal.returncode, 0, personal.stderr)
            work = self.run_browser(root, "--profile", "Work", BASE + "/work")
            self.assertEqual(work.returncode, 0, work.stderr)

            files = sorted(state_files(root))
            self.assertEqual(len(files), 2, [str(p) for p in files])
            states = [json.loads(path.read_text()) for path in files]
            tab_sets = [set(state["tabs"]) for state in states]
            self.assertTrue(any(BASE + "/personal" in tabs for tabs in tab_sets))
            self.assertTrue(any(BASE + "/work" in tabs for tabs in tab_sets))
            self.assertFalse(any(
                BASE + "/personal" in tabs and BASE + "/work" in tabs
                for tabs in tab_sets
            ))

    def test_second_launch_hands_url_to_existing_window(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            env = browser_env(root, 3200)
            first = subprocess.Popen(
                [sys.executable, str(BROWSER), BASE + "/first"],
                cwd=ROOT,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            try:
                # WebEngine can be slow on a cold CI worker. Poll the handoff
                # path instead of assuming an exact startup delay.
                second = None
                deadline = time.monotonic() + 7
                while time.monotonic() < deadline:
                    second = subprocess.run(
                        [sys.executable, str(BROWSER), BASE + "/second"],
                        cwd=ROOT,
                        env=env,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        text=True,
                        timeout=5,
                    )
                    if second.returncode == 0:
                        break
                    time.sleep(0.2)
                self.assertIsNotNone(second)
                self.assertEqual(second.returncode, 0, second.stderr)

                out, err = first.communicate(timeout=10)
                self.assertEqual(first.returncode, 0, err)
            finally:
                if first.poll() is None:
                    first.terminate()
                    first.wait(timeout=5)

            files = state_files(root)
            self.assertEqual(len(files), 1, [str(p) for p in files])
            tabs = json.loads(files[0].read_text())["tabs"]
            self.assertIn(BASE + "/first", tabs)
            self.assertIn(BASE + "/second", tabs)

    def test_production_path_is_qml_not_qtwidgets(self):
        launcher = (ROOT / "apps/browser/browser.py").read_text()
        qml = (ROOT / "apps/browser/Browser.qml").read_text()
        shell = (ROOT / "apps/browser/launch.sh").read_text()
        self.assertIn("QtWebEngineQuick.initialize", launcher)
        self.assertIn("QQmlApplicationEngine", launcher)
        self.assertNotIn("QtWidgets", launcher)
        self.assertIn("WebEngineView", qml)
        self.assertIn("Search or enter website name", qml)
        self.assertIn("Reading List", qml)
        self.assertIn("TAB GROUPS", qml)
        self.assertIn("Save Tabs as Group", qml)
        self.assertIn("Profiles", qml)
        self.assertIn("Search Engine", qml)
        self.assertIn("Separate", qml)
        self.assertIn("Compact", qml)
        self.assertIn("Tab Overview", qml)
        self.assertIn("Website Settings", qml)
        self.assertIn("listAllPermissions", qml)
        self.assertIn("DuckDuckGo", qml)
        self.assertIn("Brave", qml)
        self.assertIn("browser.py", shell)
        self.assertFalse((ROOT / "apps/browser/ui.py").exists())


if __name__ == "__main__":
    try:
        unittest.main(verbosity=2)
    finally:
        SERVER.shutdown()
