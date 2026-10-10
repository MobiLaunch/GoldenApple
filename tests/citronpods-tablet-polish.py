#!/usr/bin/env python3
"""Tablet presentation, CitronPods setup, and clipped-shadow guardrails."""
from pathlib import Path
import unittest
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

class IntegrationPolish(unittest.TestCase):
    def src(self, name):
        return (ROOT / name).read_text()

    def test_m10_source_discovery_and_one_click_setup(self):
        install = self.src("apps/citronpods/install-engine.sh")
        pane = self.src("apps/settings/panes/CitronPodsPane.qml")
        service = self.src("apps/citronpods/citronpods-daemon.service")
        self.assertIn('archive="$'+'{1:-}"', install)
        self.assertIn('--find', install)
        self.assertIn('LibrePods-CitronPods-M10-Qt6-Fixed*.zip', install)
        self.assertIn('Not a compatible CitronPods source archive', install)
        self.assertIn('cmake --build "$tmp/build" --parallel 2 --target citronpods-daemon', install)
        self.assertIn('["gg-install-citronpods", "--find"]', pane)
        self.assertIn('objectName: "citronPodsSettingsPane"', pane)
        self.assertIn('["gg-install-citronpods", pane.detectedArchive]', pane)
        self.assertIn('ExecStart=/usr/bin/env citronpods-daemon', service)

    def test_no_extra_rectangular_shadow_behind_controls(self):
        glass = self.src("apps/lib/Glass.qml")
        menu = self.src("apps/lib/MenuList.qml")
        cc = self.src("shell/ControlCenter.qml")
        hyprglass = self.src("compositor/hyprland/hyprglass-sync.sh")
        self.assertIn('property bool shadowEnabled: role !== "menu"', glass)
        self.assertIn("shadowEnabled: false", menu)
        self.assertIn("shadowEnabled: false", cc)
        self.assertNotIn('gg-controlcenter=0.25', hyprglass)
        self.assertNotIn('gg-dock,gg-controlcenter,gg-spotlight', hyprglass)
        self.assertIn('DesktopBackdrop { surface: cc;', cc)

    def test_tablet_mode_has_real_touch_consumers(self):
        prefs = self.src("shell/components/Prefs.qml")
        dock = self.src("shell/Dock.qml")
        home = self.src("shell/Applications.qml")
        control = self.src("shell/ControlCenter.qml")
        settings = self.src("apps/settings/panes/DockPane.qml")
        self.assertIn('readonly property bool tabletMode: data.tablet?.enabled ?? false', prefs)
        self.assertIn('Prefs.tabletMode ? Math.max(64, Prefs.dockSize)', dock)
        self.assertIn('Prefs.tabletMode ? (width < height ? 4 : 6)', home)
        self.assertIn('Prefs.tabletMode ? 112 : 100', home)
        self.assertIn('Prefs.tabletMode ? 54 : 48', control)
        self.assertIn('objectName: "tabletModeToggle"', settings)
        self.assertIn('pane.sys.setPref(["tablet", "enabled"], on)', settings)

    def test_tablet_keyboard_and_offline_archive_discovery(self):
        installer = ROOT / "apps/citronpods/install-engine.sh"
        with tempfile.TemporaryDirectory() as folder:
            home = Path(folder)
            downloads = home / "Downloads"
            downloads.mkdir()
            archive = downloads / "LibrePods-CitronPods-M10-Qt6-Fixed.zip"
            archive.write_bytes(b"source-is-validated-later")
            env = dict(os.environ, HOME=str(home), XDG_DOWNLOAD_DIR=str(downloads))
            proc = subprocess.run(["bash", str(installer), "--find"], env=env,
                                  text=True, capture_output=True, timeout=5)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertEqual(proc.stdout.strip(), str(archive))
            archive.unlink()
            proc = subprocess.run(["bash", str(installer), "--find"], env=env,
                                  text=True, capture_output=True, timeout=5)
            self.assertNotEqual(proc.returncode, 0)
        osk = self.src("apps/tablet/keyboard.sh")
        self.assertIn("squeekboard", osk)
        self.assertIn("sm.puri.OSK0 SetVisible", osk)
        installer_code = self.src("scripts/install.sh")
        self.assertIn('gg-tablet-keyboard', installer_code)
        packages = self.src("distro/archiso/packages.x86_64")
        self.assertIn("squeekboard", packages.splitlines())
        pane = self.src("apps/settings/panes/DockPane.qml")
        self.assertIn('["gg-tablet-keyboard", "show"]', pane)

    def test_tablet_mode_is_user_opt_in(self):
        # Never infer Tablet Mode solely from a touchscreen. Convertible users
        # may be in keyboard/laptop mode when the touch device is connected.
        self.assertIn('data.tablet?.enabled ?? false',
                      self.src("shell/components/Prefs.qml"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
