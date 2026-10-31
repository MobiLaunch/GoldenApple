#!/usr/bin/env python3
"""Typed preferences (T-2.5, CS2-023): citronos.settings and gg-pref.

Every key has a type and a default; a write that doesn't fit is refused; the
copy before each change is kept (.bak) and a damaged file is put back from
it, with the user told. And every key the shell and Settings write is in the
schema."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "apps/lib/python"))
from citronos import settings  # noqa: E402

PREF = ROOT / "apps/setup/pref-helper.py"


class Store(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        self.store = settings.Store("desktop", self.dir)

    def test_defaults_until_set(self):
        self.assertEqual(self.store.get("dock.size"), 54)
        self.assertIsNone(self.store.get("dock.pinned"))
        self.assertEqual(self.store.get("glass"), "clear")
        self.store.set("dock.size", 64)
        self.assertEqual(self.store.get("dock.size"), 64)
        self.assertEqual(json.loads(self.store.file.read_text()), {"dock": {"size": 64}})

    def test_writes_that_dont_fit_are_refused(self):
        for key, value in [("dock.size", "big"), ("dock.size", 999), ("glass", "frosted"), ("reduceMotion", 1),
                           ("dock.pinned", ["org.goldengate.Files", 3]), ("menuBar.items.wifi", "yes"),
                           ("dock.colour", "red"), ("nonsense", True), ("wallpaper", None)]:
            with self.subTest(key=key, value=value), self.assertRaises(settings.SettingsError):
                self.store.set(key, value)
        self.assertFalse(self.store.file.exists(), "nothing was written")

    def test_maps_and_open_objects(self):
        self.store.set("menuBar.items.batteryPercent", True)
        self.store.set("spotlight.apps", False)
        self.store.set("focus.session", {"until": 1234, "source": "manual"})
        self.store.set("dock.pinned", None)
        self.store.set("widgets", [{"id": "clock-1", "kind": "clock", "col": 1, "row": 0}])
        self.assertEqual(self.store.get("focus.session")["source"], "manual")

    def test_the_last_good_copy_is_kept(self):
        self.store.set("dock.size", 60)
        self.store.set("dock.size", 70)
        self.assertEqual(json.loads(self.store.backup.read_text()), {"dock": {"size": 60}})
        self.assertEqual(self.store.backup.stat().st_mode & 0o777, 0o600)

    def test_a_damaged_file_is_put_back_and_said(self):
        self.store.set("wallpaper", "/home/me/beach.jpg")
        self.store.set("dock.size", 70)
        self.store.file.write_text('{"dock": {"size": 70}, "wallp')
        self.store.set("dock.pinned", ["org.goldengate.Files"])
        saved = json.loads(self.store.file.read_text())
        self.assertEqual(saved["wallpaper"], "/home/me/beach.jpg", "the other preferences came back")
        self.assertEqual(saved["dock"]["pinned"], ["org.goldengate.Files"], "and the change was made")
        self.assertIn("put back", self.store.notice)
        kept = list(self.dir.glob("desktop.json.damaged-*"))
        self.assertEqual(len(kept), 1)
        self.assertEqual(kept[0].read_text(), '{"dock": {"size": 70}, "wallp')

    def test_with_no_good_copy_it_is_left_alone(self):
        self.store.file.write_text("[1, 2")
        with self.assertRaises(settings.SettingsError) as err:
            self.store.set("dock.size", 60)
        self.assertEqual(err.exception.code, "damaged")
        self.assertEqual(self.store.file.read_text(), "[1, 2")
        self.assertTrue(list(self.dir.glob("desktop.json.damaged-*")), "a copy is kept for repair")
        with self.assertRaises(settings.SettingsError):
            self.store.set("dock.size", 61)
        self.assertEqual(len(list(self.dir.glob("desktop.json.damaged-*"))), 1, "one copy, however often it's refused")

    def test_a_file_that_isnt_preferences_counts_as_damaged(self):
        self.store.set("dock.size", 60)
        self.store.set("dock.size", 61)
        self.store.file.write_text("[]")
        self.assertEqual(self.store.get("dock.size"), 60)


class GgPref(unittest.TestCase):
    """CS2-023's check: damage desktop.json, rearrange the Dock, restart."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)
        bin_ = self.dir / "bin"
        bin_.mkdir()
        notify = bin_ / "notify-send"
        notify.write_text(f"#!/bin/sh\nprintf '%s\\n' \"$@\" >> {self.dir}/notified\n")
        notify.chmod(0o755)
        self.env = {**os.environ, "XDG_CONFIG_HOME": str(self.dir), "PATH": f"{bin_}:{os.environ['PATH']}"}
        self.file = self.dir / "golden-gate/desktop.json"

    def pref(self, *args):
        return subprocess.run([sys.executable, str(PREF), *args], env=self.env, capture_output=True, text=True)

    def test_the_dock_survives_a_damaged_file(self):
        self.assertEqual(self.pref("wallpaper", '"/home/me/beach.jpg"').returncode, 0)
        self.assertEqual(self.pref("dock.pinned", '["org.goldengate.Files"]').returncode, 0)
        self.file.write_text('{"dock": {"pinn')                   # damaged
        p = self.pref("dock.pinned", '["org.goldengate.Files", "org.goldengate.Web"]')
        self.assertEqual(p.returncode, 0, p.stderr)
        saved = json.loads(self.file.read_text())
        self.assertEqual(saved["dock"]["pinned"], ["org.goldengate.Files", "org.goldengate.Web"])
        self.assertEqual(saved["wallpaper"], "/home/me/beach.jpg")
        self.assertIn("Preferences restored", (self.dir / "notified").read_text())

    def test_at_login_a_damaged_file_is_put_back(self):
        self.pref("dock.size", "60")
        self.pref("dock.size", "64")
        self.file.write_text("{oops")
        self.assertEqual(self.pref("--check").returncode, 0)
        self.assertEqual(json.loads(self.file.read_text()), {"dock": {"size": 60}})
        self.assertTrue((self.dir / "notified").exists())
        self.assertEqual(self.pref("--check").returncode, 0, "a good file: nothing to say")

    def test_a_wrong_value_says_why(self):
        p = self.pref("dock.size", '"huge"')
        self.assertEqual(p.returncode, 1)
        self.assertIn("dock.size should be a number", p.stderr)
        self.assertFalse(self.file.exists())

    def test_a_bare_word_is_a_string(self):
        self.assertEqual(self.pref("sound.alert", "Ping").returncode, 0)
        self.assertEqual(json.loads(self.file.read_text())["sound"]["alert"], "Ping")


class Coverage(unittest.TestCase):
    """Every desktop.json key written anywhere is in the schema."""

    def written_keys(self):
        keys = set()
        for path in list((ROOT / "apps").rglob("*.qml")) + list((ROOT / "shell").rglob("*.qml")):
            text = path.read_text(encoding="utf-8")
            for m in re.finditer(r'setPref\(\[([^\]]*)\]', text):
                parts = re.findall(r'"([A-Za-z]+)"', m.group(1))
                if parts and len(parts) == len(m.group(1).split(",")):
                    keys.add(".".join(parts))
            keys.update(re.findall(r'"gg-pref", *"([A-Za-z.]+[A-Za-z])"', text))
            keys.update(re.findall(r'Prefs\.write\("([A-Za-z.]+[A-Za-z])"', text))
            keys.update(re.findall(r'(?<![.\w])write\("([A-Za-z.]+[A-Za-z])", ', text) if path.name == "Prefs.qml" else [])
        # The dynamic ones: Dock's, Menu Bar's and Control Center's setters.
        pane = lambda name: (ROOT / "apps/settings/panes" / name).read_text(encoding="utf-8")
        keys.update("dock." + k for k in re.findall(r'setDock\("([A-Za-z]+)"', pane("DockPane.qml")))
        keys.update("menuBar." + k for k in re.findall(r'set\("([A-Za-z]+)"', pane("MenuBarPane.qml")))
        keys.update("menuBar.items." + k for k in re.findall(r'set\("([A-Za-z]+)"', pane("ControlCenterPane.qml")))
        return keys

    def test_every_written_key_is_typed(self):
        keys = self.written_keys()
        self.assertGreater(len(keys), 30)
        for key in sorted(keys):
            with self.subTest(key):
                settings.schema_for("desktop", key)

    def test_the_shells_defaults_are_the_schemas(self):
        prefs = (ROOT / "shell/components/Prefs.qml").read_text(encoding="utf-8")
        for key, default in [("dock.size", 54), ("glass", "clear"), ("sound.alert", "Crystal"),
                             ("display.warmth", 4500), ("textScale", 1)]:
            with self.subTest(key):
                self.assertEqual(settings.default("desktop", key), default)
                self.assertIn(f"?? {json.dumps(default)}", prefs)


if __name__ == "__main__":
    unittest.main()
