#!/usr/bin/env python3
"""Settings audit: persisted system options, UI routing and live consumers.

No compositor is needed. set-prefs.py is run against an isolated temp config;
the generated Hyprland fragments must match the real QML live option names.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SETTER = ROOT / "apps/settings/set-prefs.py"


class SettingsConnectivity(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory(prefix="gg-settings-test-")
        self.addCleanup(self._tmp.cleanup)
        self.config = Path(self._tmp.name) / "config"
        self.env = dict(os.environ, XDG_CONFIG_HOME=str(self.config))

    def save(self, name, *args):
        p = subprocess.run([sys.executable, str(SETTER), name, *args],
                           text=True, capture_output=True, env=self.env, timeout=10)
        try:
            answer = json.loads(p.stdout)
        except json.JSONDecodeError:
            self.fail(f"cannot read setter response: {p.stderr}, {p.stdout}")
        self.assertEqual(p.returncode, 0, answer)
        self.assertTrue(answer["ok"], answer)
        return answer["record"]

    def test_windows_are_persisted_in_a_safe_hyprland_fragment(self):
        row = self.save("windows", "snapEnabled=false", "windowGap=24",
                        "monitorGap=16", "resizeOnBorder=true", "grabArea=20")
        self.assertEqual(row["windowGap"], 24)
        config = (self.config / "hypr/golden-gate/windows.conf").read_text()
        for word in ("snap {", "enabled = false", "window_gap = 24",
                     "monitor_gap = 16", "resize_on_border = true",
                     "extend_border_grab_area = 20", "respect_gaps = true"):
            self.assertIn(word, config)
        self.save("windows", "respectGaps=false")
        saved = json.loads((self.config / "golden-gate/windows.json").read_text())
        self.assertEqual(saved["windowGap"], 24, "unrelated keys must not be lost")
        self.assertFalse(saved["respectGaps"])

    def test_conf_generation_limits_numbers_and_escapes_untrusted_values(self):
        self.save("windows", 'windowGap=9000', 'monitorGap=-8',
                  'snapEnabled="true\\nexec = rm -rf /"', "grabArea=999")
        config = (self.config / "hypr/golden-gate/windows.conf").read_text()
        self.assertIn("window_gap = 100", config)
        self.assertIn("monitor_gap = 0", config)
        self.assertIn("extend_border_grab_area = 100", config)
        self.assertNotIn("rm -rf", config)

    def test_expanded_touchpad_settings_are_persistent_and_valid(self):
        self.save("input", "naturalScroll=false", "twoFingerClick=true",
                  "disableWhileTyping=true", "tapAndDrag=false",
                  "dragLock=2", "scrollFactor=1.65")
        config = (self.config / "hypr/golden-gate/input.conf").read_text()
        for keyword in ("natural_scroll = false", "clickfinger_behavior = true",
                        "disable_while_typing = true", "tap_and_drag = false",
                        "drag_lock = 2", "scroll_factor = 1.65"):
            self.assertIn(keyword, config)
        self.save("input", "tapToClick=true")
        self.assertIn("scroll_factor = 1.65", (self.config / "hypr/golden-gate/input.conf").read_text())

    def test_settings_panes_have_live_consumers_and_navigation(self):
        qml = (ROOT / "apps/settings.qml").read_text()
        sysqml = (ROOT / "apps/settings/Sys.qml").read_text()
        dock = (ROOT / "apps/settings/panes/DockPane.qml").read_text()
        picker = (ROOT / "apps/settings/panes/DockAppsPane.qml").read_text()
        pointer = (ROOT / "apps/settings/panes/TrackpadPane.qml").read_text()
        appearance = (ROOT / "apps/settings/panes/AppearancePane.qml").read_text()
        hypr = (ROOT / "compositor/hyprland/hyprland.conf").read_text()
        install = (ROOT / "scripts/install.sh").read_text()
        updater = (ROOT / "apps/settings/golden_update.py").read_text()
        prefs = (ROOT / "shell/components/Prefs.qml").read_text()
        dock_shell = (ROOT / "shell/Dock.qml").read_text()

        for needle in ('file: "DockAppsPane"', 'objectName: "settingsSidebarToggle"',
                       'current: Quickshell.env("GG_SETTINGS_PANE") || "general"'):
            self.assertIn(needle, qml)
        for option in ("snapEnabled", "windowGap", "monitorGap", "respectGaps", "resizeOnBorder", "grabArea"):
            self.assertIn(f'"{option}"', dock)
            self.assertIn(f'{option}: "general:', sysqml)
        for option in ("twoFingerClick", "disableWhileTyping", "tapAndDrag", "scrollFactor", "dragLock"):
            self.assertIn(option, pointer)
            self.assertIn(option, sysqml)
        self.assertIn('pane.sys.prefs.glassWindows ?? true', appearance)
        self.assertIn('readonly property bool glassWindows', prefs)
        self.assertIn('readonly property bool dockShowRecents', prefs)
        self.assertIn('Prefs.dockShowRecents', dock_shell)
        self.assertIn('source = ~/.config/hypr/golden-gate/windows.conf', hypr)
        self.assertIn('accessibility displays windows', install)
        self.assertIn('"hypr/golden-gate/windows.conf"', updater)
        self.assertIn('DesktopEntries.applications.values', picker)
        self.assertIn('pane.sys.setPref(["dock", "pinned"]', picker)
        self.assertIn('dex --autostart --environment Hyprland', hypr)
        self.assertIn('dex', (ROOT / "distro/archiso/packages.x86_64").read_text().splitlines())
        self.assertIn('"glassWindows"', (ROOT / "apps/settings/Sys.qml").read_text())

    def test_existing_settings_panes_still_have_real_handlers(self):
        required = {
            "WifiPane.qml": "nmcli",
            "BluetoothPane.qml": "bluetoothctl",
            "SoundPane.qml": "wpctl",
            "DisplaysPane.qml": "hyprctl",
            "BatteryPane.qml": "upower",
            "WallpaperPane.qml": 'sys.setPref(["wallpaper"]',
            "MenuBarPane.qml": '"menuBar"',
            "ControlCenterPane.qml": '"menuBar"',
            "NotificationsPane.qml": '"notifications"',
            "LockScreenPane.qml": '"lockScreen"',
            "NetworkPane.qml": '"nmcli"',
        }
        for name, needle in required.items():
            source = (ROOT / "apps/settings/panes" / name).read_text()
            self.assertIn(needle, source, f"settings pane must connect to a real source: {name}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
