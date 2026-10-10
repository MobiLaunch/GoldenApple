#!/usr/bin/env python3
"""CitronPods Golden Gate integration: backend installer and shell contracts."""
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
INSTALL = ROOT / "apps/citronpods/install-engine.sh"


class CitronPodsIntegration(unittest.TestCase):
    def test_shell_owns_one_popup_and_native_settings(self):
        shell = (ROOT / "shell/shell.qml").read_text()
        cc = (ROOT / "shell/ControlCenter.qml").read_text()
        popup = (ROOT / "shell/CitronPodsPopup.qml").read_text()
        service = (ROOT / "apps/lib/CitronPodsService.qml").read_text()
        settings = (ROOT / "apps/settings.qml").read_text()
        bluetooth = (ROOT / "apps/settings/panes/BluetoothPane.qml").read_text()
        pane = (ROOT / "apps/settings/panes/CitronPodsPane.qml").read_text()
        self.assertIn('source: "CitronPodsPopup.qml"', shell)
        self.assertIn('objectName: "citronPodsSystemPopup"', popup)
        self.assertIn('Shared.CitronPodsService', cc)
        self.assertIn('Shared.CitronPodsService', popup)
        self.assertIn('shadowEnabled: false', popup)
        self.assertIn('CitronPodsService {', pane)
        self.assertIn('["", "wifi", "bluetooth", "sound"', cc)
        self.assertIn('airpods: "AirPods"', cc)
        self.assertIn('"airpods", "AirPods"', settings)
        self.assertIn('pane.nav.open("airpods")', bluetooth)
        self.assertIn('org.citronos.CitronPods1', service)
        self.assertIn('state.json', service)
        self.assertIn('if (seen && oldSeq >= 0 && seq > oldSeq', service)
        self.assertIn('activeDevice.trusted === true', service)
        self.assertIn('if (canControl && Number.isInteger(mode)', service)
        self.assertNotIn('citronpods -n', popup)

    def test_clipped_control_center_and_context_shadows_disabled(self):
        glass = (ROOT / "apps/lib/Glass.qml").read_text()
        menu = (ROOT / "apps/lib/MenuList.qml").read_text()
        control = (ROOT / "shell/ControlCenter.qml").read_text()
        self.assertIn('property bool shadowEnabled: role === "control" || role === "sidebar" || role === "dock"', glass)
        self.assertIn('visible: root.shadowEnabled &&', glass)
        self.assertIn('shadowEnabled: false', menu)
        self.assertIn('shadowEnabled: false', control)
        self.assertIn('lens: 13', control)

    def test_native_engine_is_installed_only_when_user_supplies_m10(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            archive = home / "m10.zip"
            prefix = "librepods-main/"
            required = {
                "citronos/CMakeLists.txt": b"cmake_minimum_required(VERSION 3.21)",
                "citronos/src/daemonmain.cpp": b"int main() { return 0; }",
                "citronos/src/ProtocolBridge.cpp": b"QBluetoothSocket::SocketState::UnconnectedState",
                "citronos/src/PodManager.cpp": b"void example() {}",
                "linux/battery.hpp": b"#pragma once",
                "linux/airpods_packets.h": b"#pragma once",
            }
            with zipfile.ZipFile(archive, "w") as f:
                for path, data in required.items():
                    f.writestr(prefix + path, data)
            tools = home / "tools"
            tools.mkdir()
            cmake = tools / "cmake"
            cmake.write_text(
                '#!/bin/sh\n'
                'if [ "$1" = "-S" ]; then mkdir -p "$4"; fi\n'
                'if [ "$1" = "--build" ]; then\n'
                '  printf "#!/bin/sh\\nexit 0\\n" > "$2/citronpods-daemon"\n'
                '  chmod +x "$2/citronpods-daemon"\n'
                'fi\n'
                'exit 0\n'
            )
            cmake.chmod(0o755)
            systemctl = tools / "systemctl"
            systemctl.write_text("#!/bin/sh\nexit 0\n")
            systemctl.chmod(0o755)
            env = {
                **os.environ, "HOME": str(home),
                "XDG_CONFIG_HOME": str(home / ".config"),
                "GG_CITRONPODS_UNIT": str(ROOT / "apps/citronpods/citronpods-daemon.service"),
                "PATH": str(tools) + os.pathsep + os.environ.get("PATH", ""),
            }
            p = subprocess.run(["bash", str(INSTALL), str(archive)], env=env,
                               text=True, capture_output=True, timeout=40)
            self.assertEqual(p.returncode, 0, p.stderr + p.stdout)
            self.assertTrue((home / ".local/bin/citronpods-daemon").is_file())
            self.assertTrue((home / ".config/systemd/user/citronpods-daemon.service").is_file())
            self.assertIn('only the daemon', p.stdout)
            self.assertFalse((home / ".local/bin/citronpods").exists())

            bad = home / "old.zip"
            with zipfile.ZipFile(bad, "w") as f:
                for path, data in required.items():
                    if path.endswith("ProtocolBridge.cpp"):
                        data = b"QBluetoothSocket::UnconnectedState"
                    f.writestr(prefix + path, data)
            old = subprocess.run(["bash", str(INSTALL), str(bad)], env=env,
                                 text=True, capture_output=True, timeout=35)
            self.assertNotEqual(old.returncode, 0)
            self.assertIn("Qt Bluetooth enum error", old.stderr)

    def test_staged_system_install_and_dependencies(self):
        installer = (ROOT / "scripts/install.sh").read_text()
        packages = (ROOT / "distro/archiso/packages.x86_64").read_text()
        service = (ROOT / "apps/citronpods/citronpods-daemon.service").read_text()
        self.assertIn("qt6-connectivity", packages)
        self.assertIn("libpulse", packages)
        self.assertIn('citronpods-daemon.service', installer)
        self.assertIn('"$BIN/gg-install-citronpods"', installer)
        self.assertIn('"$BIN/gg-citronpods"', installer)
        self.assertIn('Environment=PATH=%h/.local/bin:/usr/local/bin:/usr/bin', service)
        self.assertIn('ExecStart=/usr/bin/env citronpods-daemon', service)
        self.assertIn('NoNewPrivileges=true', service)


if __name__ == "__main__":
    unittest.main(verbosity=2)
