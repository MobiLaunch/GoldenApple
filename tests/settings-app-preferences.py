#!/usr/bin/env python3
"""Default Apps and Login Items: isolated XDG behavior, no system mutation."""
from pathlib import Path
import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "apps/settings/app-preferences.py"


class ApplicationPreferences(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="gg-app-prefs-")
        self.addCleanup(self.tmp.cleanup)
        p = Path(self.tmp.name)
        self.data = p / "data"
        self.config = p / "config"
        self.system = p / "system"
        self.system_config = p / "etc"
        for x in (self.data, self.config, self.system, self.system_config):
            x.mkdir()
        (self.data / "applications").mkdir()
        app = self.data / "applications/org.test.Editor.desktop"
        app.write_text("[Desktop Entry]\nType=Application\nName=Test Editor\nExec=editor %f\nMimeType=text/plain;application/zip;\n")
        (self.system_config / "autostart").mkdir()
        (self.system_config / "autostart/org.test.Background.desktop").write_text(
            "[Desktop Entry]\nType=Application\nName=System Helper\nExec=helper\n")
        binary = p / "bin"
        binary.mkdir()
        mock = binary / "xdg-mime"
        # This test-only binary implements query + default and records changes.
        mock.write_text("#!/bin/sh\n"
                        'if [ "$1" = query ]; then [ -f "$TEST_MIME_STATE" ] && cat "$TEST_MIME_STATE"; exit 0; fi\n'
                        'if [ "$1" = default ]; then printf "%s" "$2" > "$TEST_MIME_STATE"; exit 0; fi\n'
                        'exit 1\n')
        mock.chmod(0o755)
        self.state = p / "mime"
        self.env = dict(os.environ, XDG_CONFIG_HOME=str(self.config),
                        XDG_DATA_HOME=str(self.data), XDG_DATA_DIRS=str(self.system),
                        XDG_CONFIG_DIRS=str(self.system_config),
                        TEST_MIME_STATE=str(self.state),
                        PATH=str(binary) + os.pathsep + os.environ.get("PATH", ""))

    def run_helper(self, *args):
        proc = subprocess.run([sys.executable, str(HELPER), *args],
                              env=self.env, text=True, capture_output=True, timeout=8)
        try:
            body = json.loads(proc.stdout)
        except ValueError:
            self.fail(proc.stderr + proc.stdout)
        return proc.returncode, body

    def test_default_apps_use_installed_mime_handlers_and_verify_selected(self):
        code, result = self.run_helper("defaults")
        self.assertEqual(code, 0, result)
        entries = {r["mime"]: r for r in result["rows"]}
        self.assertIn("org.test.Editor.desktop", [r["id"] for r in entries["text/plain"]["choices"]])
        code, result = self.run_helper("set-default", "text/plain", "org.test.Editor.desktop")
        self.assertEqual(code, 0, result)
        self.assertEqual(self.state.read_text(), "org.test.Editor.desktop")
        self.assertEqual(next(r for r in result["rows"] if r["mime"] == "text/plain")["current"],
                         "org.test.Editor.desktop")

    def test_default_apps_reject_injected_mime_or_desktop_id(self):
        for target in (("text/plain", "../../x.desktop"), ("application/x-unsafe", "org.test.Editor.desktop"),
                       ("text/plain", "org.test.Background.desktop")):
            code, result = self.run_helper("set-default", *target)
            self.assertNotEqual(code, 0)
            self.assertFalse(result["ok"])

    def test_autostart_overrides_and_adding_apps(self):
        code, result = self.run_helper("login-items")
        self.assertEqual(code, 0)
        self.assertTrue(next(x for x in result["rows"] if x["id"] == "org.test.Background.desktop")["enabled"])
        code, result = self.run_helper("toggle-login", "org.test.Background.desktop", "false")
        self.assertEqual(code, 0, result)
        self.assertFalse(next(x for x in result["rows"] if x["id"] == "org.test.Background.desktop")["enabled"])
        override = self.config / "autostart/org.test.Background.desktop"
        self.assertIn("Hidden = true", override.read_text())
        code, result = self.run_helper("toggle-login", "org.test.Editor.desktop", "true")
        self.assertEqual(code, 0, result)
        added = self.config / "autostart/org.test.Editor.desktop"
        self.assertTrue(added.exists())
        self.assertIn("Exec=editor %f", added.read_text())
        code, result = self.run_helper("toggle-login", "org.test.Editor.desktop", "false")
        self.assertEqual(code, 0, result)
        self.assertIn("Hidden = true", added.read_text())

    def test_autostart_rejects_traversal_and_symbolic_links(self):
        code, result = self.run_helper("toggle-login", "../../outside.desktop", "true")
        self.assertNotEqual(code, 0)
        startup = self.config / "autostart"
        startup.mkdir(exist_ok=True)
        (startup / "org.test.Editor.desktop").symlink_to(self.state)
        code, result = self.run_helper("toggle-login", "org.test.Editor.desktop", "true")
        self.assertNotEqual(code, 0)

    def test_general_settings_references_panels_and_helper(self):
        page = (ROOT / "apps/settings.qml").read_text()
        general = (ROOT / "apps/settings/panes/GeneralPane.qml").read_text()
        for name in ("DefaultAppsPane", "LoginItemsPane", "DockAppsPane"):
            self.assertIn(name, page)
            self.assertTrue((ROOT / "apps/settings/panes" / (name + ".qml")).is_file())
        for key in ("defaultapps", "loginitems"):
            self.assertIn('pane.nav.push("' + key + '")', general)
        for path in ("DefaultAppsPane.qml", "LoginItemsPane.qml"):
            self.assertIn("app-preferences.py",
                          (ROOT / "apps/settings/panes" / path).read_text())


if __name__ == "__main__":
    unittest.main(verbosity=2)
