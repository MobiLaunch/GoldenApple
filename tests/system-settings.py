#!/usr/bin/env python3
"""Settings' system panes and what follows them: Lock Screen's timers
(gg-idle writes hypridle.conf), and the shell (MacShell, with its CitronOS
patches) reading the Notifications, Focus, Dock and Lock Screen choices that
the panes write."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
IDLE = ROOT / "compositor/hyprland/idle.py"


def idle(lock=None):
    with tempfile.TemporaryDirectory() as d:
        if lock is not None:
            (Path(d) / "golden-gate").mkdir()
            (Path(d) / "golden-gate/desktop.json").write_text(json.dumps({"lockScreen": lock}))
        return subprocess.run([sys.executable, str(IDLE), "--print"], env={**os.environ, "XDG_CONFIG_HOME": d},
                              capture_output=True, text=True, check=True).stdout


def listeners(conf):
    return [(int(t), on.strip()) for t, on in re.findall(r"timeout = (\d+)\n\s+on-timeout = ([^\n]+)", conf)]


class LockScreen(unittest.TestCase):
    def test_shipped_config_is_the_default(self):
        self.assertEqual(idle(), (ROOT / "compositor/hyprland/hypridle.conf").read_text())

    def test_timers_follow_the_pane(self):
        got = listeners(idle({"displayOff": 1200, "requireAfter": 60, "dim": True}))
        self.assertIn((600, "brightnessctl -s set 20%"), got)
        self.assertIn((1200, """hyprctl dispatch 'hl.dsp.dpms({ action = "disable" })'"""), got)
        self.assertIn((1260, "loginctl lock-session"), got)

    def test_never(self):
        conf = idle({"displayOff": 0})
        self.assertEqual(listeners(conf), [], "the display never turns off, so nothing locks by idling")
        self.assertIn("before_sleep_cmd = loginctl lock-session", conf, "sleep still locks")
        got = listeners(idle({"displayOff": 300, "requireAfter": -1, "dim": False}))
        self.assertEqual(got, [(300, """hyprctl dispatch 'hl.dsp.dpms({ action = "disable" })'""")])

    def test_bad_values_fall_back(self):
        self.assertEqual(idle({"displayOff": "soon", "dim": "yes"}), idle())

    def test_installed_everywhere(self):
        install = (ROOT / "scripts/install.sh").read_text()
        self.assertEqual(install.count('> "$BIN/gg-idle"'), 3, "gg-idle for every install mode")
        self.assertIn("/usr/local/bin/gg-idle", (ROOT / "distro/archiso/build.sh").read_text())


class Panes(unittest.TestCase):
    def setUp(self):
        src = (ROOT / "apps/settings.qml").read_text()
        self.panes = re.findall(r'\[\d, "([a-z]+)", "[^"]+", "[^"]+", "#[0-9a-f]{6}", "([A-Za-z]+)"', src)
        self.subpages = re.findall(r'^\s+([a-z]+): \{ title:', src, re.M)

    def test_every_pane_has_a_file(self):
        for _, file in self.panes:
            self.assertTrue((ROOT / f"apps/settings/panes/{file}.qml").exists(), file)
        for pane in ("controlcenter", "notifications", "lockscreen", "spotlight"):
            self.assertIn(pane, dict(self.panes))


class ShellFollows(unittest.TestCase):
    """The shell reads what the panes write (desktop.json keys)."""

    def test_keys_match(self):
        bar = (ROOT / "shell/macshell/MacBar.qml").read_text()
        prefs = (ROOT / "shell/components/Prefs.qml").read_text()
        for field in ("allow", "banners", "sound"):
            self.assertIn(f"ggChoice.{field}", bar)
            self.assertIn(field, prefs)
        self.assertIn("Prefs.notifyPreviews", bar)
        self.assertIn("Prefs.focusStatus.permits(", bar)
        self.assertIn(".lockScreen.message", (ROOT / "shell-lock/shell.qml").read_text())
        dock = (ROOT / "shell/macshell/MacDock.qml").read_text()
        sys_qml = (ROOT / "apps/settings/Sys.qml").read_text()
        self.assertIn('/.config/macdock/pinned.json', sys_qml)
        self.assertIn('path: root.configDir + "/pinned.json"', dock)
        self.assertRegex(dock, r'pinned\.json"\n\s+printErrors: false\n(\s+//.*\n)?\s+watchChanges: true')

if __name__ == "__main__":
    unittest.main()
