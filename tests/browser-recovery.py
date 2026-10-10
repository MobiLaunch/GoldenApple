#!/usr/bin/env python3
"""Exercise the actual Web launcher without Qt/GPU hardware, using a fake Python.

In particular, a renderer or native crash must retry only once with software
graphics; ordinary Python/QML failures and already-safe failures must not loop.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
LAUNCH = ROOT / "apps/browser/launch.sh"

# Substitute just the launched Python executable; the real Web source is
# unchanged. Record the flags and CLI arguments for each browser invocation.
SHIM = """#!/bin/sh
printf '%s|%s|%s\\n' "${LIBGL_ALWAYS_SOFTWARE:-0}" "${QTWEBENGINE_CHROMIUM_FLAGS:-}" "$*" >> "$WEB_TEST_CALLS"
case "$WEB_TEST_MODE" in
  abort-once) test "$(wc -l < "$WEB_TEST_CALLS")" -eq 1 && exit 139 ;;
  renderer-once) test "$(wc -l < "$WEB_TEST_CALLS")" -eq 1 && exit 79 ;;
  xcb-rescue) test "${QT_QPA_PLATFORM:-}" = xcb || exit 139 ;;
  qml-error) exit 2 ;;
  abort-always) exit 139 ;;
esac
exit 0
"""


class BrowserRecovery(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        bindir = self.home / "bin"
        bindir.mkdir()
        fake = bindir / "python3"
        fake.write_text(SHIM)
        fake.chmod(0o755)
        self.calls = self.home / "calls"
        self.env = os.environ.copy()
        self.env.update(
            PATH=str(bindir) + os.pathsep + self.env.get("PATH", ""),
            HOME=str(self.home),
            XDG_STATE_HOME=str(self.home / "state"),
            WEB_TEST_CALLS=str(self.calls),
        )
        for key in ("LIBGL_ALWAYS_SOFTWARE", "GG_WEB_SOFTWARE", "GG_WEB_LIVE_SAFE",
                    "QT_QUICK_BACKEND", "QTWEBENGINE_CHROMIUM_FLAGS"):
            self.env.pop(key, None)

    def launch(self, mode):
        return subprocess.run(
            ["sh", str(LAUNCH), "--private", "https://example.com"],
            env={**self.env, "WEB_TEST_MODE": mode},
            text=True, capture_output=True, timeout=10,
        )

    def lines(self):
        return self.calls.read_text().splitlines()

    def test_native_abort_retries_once_without_erasing_data(self):
        state = self.home / "state" / "golden-gate"
        state.mkdir(parents=True)
        saved = state / "keep.json"
        saved.write_text('{"important":true}')
        result = self.launch("abort-once")
        self.assertEqual(result.returncode, 0, result.stderr)
        attempts = self.lines()
        self.assertEqual(len(attempts), 2)
        self.assertTrue(attempts[0].startswith("0|"), attempts)
        self.assertTrue(attempts[1].startswith("1|"), attempts)
        self.assertIn("--disable-gpu", attempts[1])
        self.assertIn("--disable-features=Vulkan", attempts[1])
        self.assertIn("--private https://example.com", attempts[1])
        self.assertEqual(saved.read_text(), '{"important":true}')
        self.assertTrue((state / "web-safe-mode").exists())
        self.assertEqual((state / "web.log").stat().st_mode & 0o777, 0o600)

    def test_renderer_request_restarts_in_safe_mode(self):
        result = self.launch("renderer-once")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.lines()), 2)
        self.assertIn("--disable-gpu", self.lines()[1])

    def test_wayland_crash_tries_xwayland_after_software_gl(self):
        self.env["WAYLAND_DISPLAY"] = "wayland-1"
        self.env["DISPLAY"] = ":0"
        result = self.launch("xcb-rescue")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.lines()), 3, self.lines())
        state = self.home / "state/golden-gate"
        self.assertTrue((state / "web-xcb-mode").exists())
        self.assertTrue((state / "web-safe-mode").exists())

    def test_existing_safe_mode_can_switch_to_xwayland(self):
        self.env["WAYLAND_DISPLAY"] = "wayland-1"
        self.env["DISPLAY"] = ":0"
        self.env["GG_WEB_SOFTWARE"] = "1"
        result = self.launch("xcb-rescue")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.lines()), 2)

    def test_qml_failure_does_not_relaunch(self):
        result = self.launch("qml-error")
        self.assertEqual(result.returncode, 2)
        self.assertEqual(len(self.lines()), 1)
        log = (self.home / "state/golden-gate/web.log").read_text()
        self.assertIn("status 2", log)

    def test_safe_mode_never_enters_crash_loop(self):
        self.env["GG_WEB_SOFTWARE"] = "1"
        result = self.launch("abort-always")
        self.assertEqual(result.returncode, 139)
        self.assertEqual(len(self.lines()), 1)
        self.assertIn("--disable-gpu", self.lines()[0])


class SharedThemeImportRegression(unittest.TestCase):
    def test_native_web_can_import_shared_theme_without_quickshell(self):
        theme = (ROOT / "apps/lib/theme/Touch.qml").read_text()
        app_window = (ROOT / "apps/lib/AppWindow.qml").read_text()
        self.assertIn("import QtQuick", theme)
        self.assertNotIn("import Quickshell", theme)
        self.assertNotIn("FileView {", theme)
        self.assertIn("onTabletEnabledChanged: Touch.enabled = tabletEnabled", app_window)


if __name__ == "__main__":
    unittest.main()
