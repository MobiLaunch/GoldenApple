#!/usr/bin/env python3
"""Settings' system panes and what follows them: Lock Screen's timers
(gg-idle writes hypridle.conf), Spotlight finding every pane, and the shell
reading the Control Center, Notifications, Spotlight and Lock Screen
choices that the panes write."""
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
        self.assertIn((1200, "hyprctl dispatch dpms off"), got)
        self.assertIn((1260, "loginctl lock-session"), got)

    def test_never(self):
        conf = idle({"displayOff": 0})
        self.assertEqual(listeners(conf), [], "the display never turns off, so nothing locks by idling")
        self.assertIn("before_sleep_cmd = loginctl lock-session", conf, "sleep still locks")
        got = listeners(idle({"displayOff": 300, "requireAfter": -1, "dim": False}))
        self.assertEqual(got, [(300, "hyprctl dispatch dpms off")])

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

    def test_spotlight_finds_every_pane(self):
        answers = (ROOT / "shell/spotlight/answers.js").read_text()
        indexed = set(re.findall(r'^\s+\["([a-z]+)", "', answers, re.M))
        ids = {p for p, _ in self.panes} | set(self.subpages)
        self.assertEqual(ids - indexed, set(), "panes Spotlight can't find")
        self.assertEqual(indexed - ids, set(), "Spotlight opens panes that don't exist")


class ShellFollows(unittest.TestCase):
    """The shell reads what the panes write (desktop.json keys)."""

    def test_keys_match(self):
        prefs = (ROOT / "shell/components/Prefs.qml").read_text()
        cc = (ROOT / "apps/settings/panes/ControlCenterPane.qml").read_text()
        for key in re.findall(r'pane\.set\("([a-zA-Z]+)"', cc):
            self.assertIn(f"barItems.{key}", prefs, key)
        spot = (ROOT / "apps/settings/panes/SpotlightPane.qml").read_text()
        shell_spot = (ROOT / "shell/Spotlight.qml").read_text()
        for kind in re.findall(r'\["([a-z]+)", "[A-Z]', spot):
            self.assertIn(f'spotlightShows("{kind}")', shell_spot, kind)
        notes = (ROOT / "shell/Notifications.qml").read_text()
        for field in ("allow", "banners", "sound", "badges"):
            self.assertIn(field, notes)
        self.assertIn("Prefs.notifyPreviews", notes)
        self.assertIn("message: Prefs.lockMessage", (ROOT / "shell/LockScreen.qml").read_text())


if __name__ == "__main__":
    unittest.main()
