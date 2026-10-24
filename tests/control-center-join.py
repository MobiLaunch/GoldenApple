#!/usr/bin/env python3
"""Control Center joins a Wi-Fi network without letting its name be read as a
command. SSIDs come from the air, so one named $(…) or `…` must reach nmcli as
those very characters (CS2-002).

Production ControlCenter.qml is loaded in the preview harness; the command it
asks for is then run for real against stub nmcli and gg-settings programs.
"""
import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("control_center", ROOT / "tests/control-center.py")
cc_tests = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cc_tests)

NASTY = ['$(touch "$MARK")', '`touch "$MARK"`', 'Cafe"; touch "$MARK"; "', "it's \\ a $HOME net", 'a\nb']


class WifiJoin(cc_tests.harness.Harness):
    desktop = cc_tests.GoldenGateControls.desktop

    def requested(self):
        """The argv of each command Control Center asked to run, in order."""
        out = []
        for line in self.system.logs:
            if line.startswith("exec "):
                out.append(json.loads(line[5:]))
            self.assertFalse(line.startswith("hyprland exec"), "a command went to Hyprland's sh -c: " + line)
        return out

    def run_stubbed(self, argv):
        with tempfile.TemporaryDirectory() as tmp:
            bin_dir, mark, record = Path(tmp) / "bin", Path(tmp) / "pwned", Path(tmp) / "args"
            bin_dir.mkdir()
            for name in ("nmcli", "gg-settings"):
                stub = bin_dir / name
                stub.write_text('#!/bin/sh\nfor a in "$@"; do printf "%s\\0" "$a"; done >> "$RECORD"\n'
                                'printf "\\001" >> "$RECORD"\nexit 1\n')
                stub.chmod(stub.stat().st_mode | stat.S_IXUSR)
            env = {"PATH": f"{bin_dir}:/usr/bin:/bin", "MARK": str(mark), "RECORD": str(record)}
            subprocess.run(argv, env=env, timeout=10)
            calls = [c.split("\0")[:-1] for c in record.read_text().split("\x01") if c] if record.exists() else []
            return mark.exists(), calls

    def test_ssids_are_passed_literally(self):
        cc = self.desktop("shell/ControlCenter.qml", "controlCenter", width=440, height=800)
        for ssid in NASTY:
            self.system.logs.clear()
            self.eval(cc, "joinNetwork(" + json.dumps(ssid) + ")")
            QTest.qWait(10)
            commands = self.requested()
            self.assertEqual(len(commands), 1, commands)
            argv = commands[0]
            self.assertEqual(argv[-1], ssid, "the name is its own argument")
            self.assertNotIn(ssid, " ".join(argv[:-1]), "the name is not inside the script")
            pwned, calls = self.run_stubbed(argv)
            self.assertFalse(pwned, f"the SSID {ssid!r} ran a command")
            self.assertEqual(calls[0], ["-w", "15", "connection", "up", "id", ssid])
            self.assertEqual(calls[1], ["-w", "15", "device", "wifi", "connect", ssid])
            self.assertEqual(calls[2], ["wifi"], "a network it can't join opens Settings")

    def test_no_command_is_a_shell_string(self):
        cc = self.desktop("shell/ControlCenter.qml", "controlCenter", width=440, height=800)
        self.system.logs.clear()
        for call in ("openDetailSettings()", "setDarkMode()", "setNightShift()", "ipc('missioncontrol toggle')"):
            if call == "openDetailSettings()":
                self.eval(cc, "detail = 'wifi'")
            self.eval(cc, call)
        self.eval(cc, "setBrightness(0.5)")
        QTest.qWait(80)
        commands = self.requested()
        self.assertIn(["gg-settings", "wifi"], commands)
        self.assertIn(["qs", "-c", "golden-gate", "ipc", "call", "missioncontrol", "toggle"], commands)
        self.assertTrue(any(c[:3] == ["brightnessctl", "-q", "set"] for c in commands), commands)


if __name__ == "__main__":
    unittest.main()
