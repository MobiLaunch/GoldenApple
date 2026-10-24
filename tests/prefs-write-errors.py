#!/usr/bin/env python3
"""A preference change the shell can't save is put back and said (CS2-023).

The shell shows a change at once and saves it with gg-pref. If the save
fails (a damaged desktop.json, a full disk), the change used to stay on
screen and vanish at the next login. Now it is undone, unless something
changed it again meanwhile, and a notification says why. Production
ControlCenter.qml and Prefs.qml run in the preview harness; gg-pref runs for
real in a temporary home, or fails when told to.
"""
import importlib.util
import json
from pathlib import Path
import unittest
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[1]
cc_spec = importlib.util.spec_from_file_location("control_center", ROOT / "tests/control-center.py")
cc_tests = importlib.util.module_from_spec(cc_spec)
cc_spec.loader.exec_module(cc_tests)
harness = cc_tests.harness          # the one Qt application, from focus-ui.py


class PrefWrites(harness.Harness):
    desktop = cc_tests.GoldenGateControls.desktop

    def notices(self):
        return [json.loads(l[5:]) for l in self.system.logs
                if l.startswith("exec ") and '"notify-send"' in l]

    def test_saved_when_it_can_be(self):
        cc = self.desktop("shell/ControlCenter.qml", "controlCenter", width=440, height=800)
        self.eval(cc, "Prefs.setDockPinned(['org.goldengate.Files', 'org.goldengate.Notes'])")
        QTest.qWait(200)
        saved = json.loads((self.home / "config/golden-gate/desktop.json").read_text())
        self.assertEqual(saved["dock"]["pinned"], ["org.goldengate.Files", "org.goldengate.Notes"])
        self.assertEqual(self.eval(cc, "Prefs.keptInDock"), ["org.goldengate.Files", "org.goldengate.Notes"])
        self.assertEqual(self.notices(), [])

    def test_a_failed_save_is_undone_and_said(self):
        cc = self.desktop("shell/ControlCenter.qml", "controlCenter", width=440, height=800)
        before = self.eval(cc, "Prefs.keptInDock")
        self.system.fail = True
        self.eval(cc, "Prefs.setDockPinned(['org.goldengate.Files'])")
        self.wait_for(cc, "Prefs.saveError !== ''")
        QTest.qWait(50)
        self.assertEqual(self.eval(cc, "Prefs.keptInDock"), before, "the Dock is as it was")
        notes = self.notices()
        self.assertEqual(len(notes), 1, self.system.logs)
        self.assertIn("Dock change wasn't saved", notes[0][-2])
        self.assertIn("disk full", notes[0][-1])

    def test_a_damaged_file_is_kept_and_named(self):
        # The real gg-pref, on a desktop.json that isn't JSON: the file stays
        # as it is, one copy is kept however often it's refused, and the
        # notification says where.
        conf = self.home / "config/golden-gate"
        conf.mkdir(parents=True, exist_ok=True)
        (conf / "desktop.json").write_text('{"dock": {"pinned": [')
        cc = self.desktop("shell/ControlCenter.qml", "controlCenter", width=440, height=800)
        for ids in (["org.goldengate.Files"], ["org.goldengate.Notes"]):
            self.eval(cc, "Prefs.saveError = ''")
            self.eval(cc, f"Prefs.setDockPinned({json.dumps(ids)})")
            self.wait_for(cc, "Prefs.saveError !== ''")
        self.assertEqual((conf / "desktop.json").read_text(), '{"dock": {"pinned": [')
        copies = list(conf.glob("desktop.json.damaged-*"))
        self.assertEqual(len(copies), 1, copies)
        self.assertEqual(copies[0].read_text(), '{"dock": {"pinned": [')
        notes = self.notices()
        self.assertEqual(len(notes), 2)
        self.assertIn(copies[0].name, notes[-1][-1])

    def test_control_center_and_night_shift_use_it_too(self):
        cc = self.desktop("shell/ControlCenter.qml", "controlCenter", width=440, height=800)
        self.system.fail = True
        self.eval(cc, "setExtras(['screenshot', 'timer'])")
        self.wait_for(cc, "Prefs.saveError !== ''")
        QTest.qWait(50)
        self.assertNotIn("timer", [e["id"] for e in self.eval(cc, "extras")])
        self.assertTrue(any("Control Center change" in n[-2] for n in self.notices()))
        for line in self.system.logs:
            self.assertFalse(line.startswith("exec ") and '"gg-pref"' in line,
                             "no gg-pref is started without watching its result: " + line)


if __name__ == "__main__":
    unittest.main()
