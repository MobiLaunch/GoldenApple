#!/usr/bin/env python3
"""CitronPods M10 shell service auto-setup, without live Bluetooth or Qt."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BOOTSTRAP = ROOT / "apps/citronpods/bootstrap.sh"


class NativeAirPodsBootstrap(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.bin = self.home / ".local/bin"
        self.bin.mkdir(parents=True)
        self.log = self.home / "calls.txt"
        self.env = {**os.environ, "HOME": str(self.home),
                    "XDG_STATE_HOME": str(self.home / ".local/state"),
                    "FAKE_CALLS": str(self.log)}
        self.install_mock = self.bin / "gg-install-citronpods"
        self.systemctl = self.bin / "systemctl"
        self.systemctl.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$FAKE_CALLS"\n')
        self.systemctl.chmod(0o755)

    def install_stub(self, script):
        self.install_mock.write_text("#!/bin/sh\n" + script)
        self.install_mock.chmod(0o755)

    def boot(self):
        return subprocess.run(["bash", str(BOOTSTRAP)], env=self.env,
                              text=True, capture_output=True, timeout=15)

    def test_source_missing_is_quiet_and_does_not_install_fake_daemon(self):
        self.install_stub('if [ "$1" = "--find" ]; then exit 1; fi\nexit 8\n')
        p = self.boot()
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn("Engine pending", (self.home / ".local/state/golden-gate/citronpods-engine-status").read_text())
        self.assertFalse((self.bin / "citronpods-daemon").exists())
        self.assertFalse(self.log.exists())

    def test_source_available_builds_once_and_starts_service(self):
        archive = self.home / "Downloads/LibrePods-CitronPods-M10-Qt6-Fixed.zip"
        archive.parent.mkdir()
        archive.write_bytes(b"placeholder")
        # The real daemon auto-setup requires the trusted M10 SHA-256. Test
        # its success path with a deterministic digest shim; no proprietary
        # Bluetooth protocol or compiler is needed on CI.
        digest = self.bin / "sha256sum"
        digest.write_text(
            '#!/bin/sh\n'
            'printf "%s  %s\\n" "d14d3e74efb716357713d024bcb7c2311ae1226d8fa6bb883f4b9237661b4da4" "$2"\n'
        )
        digest.chmod(0o755)
        self.install_stub(
            'if [ "$1" = "--find" ]; then printf "%s\\n" "$HOME/Downloads/LibrePods-CitronPods-M10-Qt6-Fixed.zip"; exit 0; fi\n'
            'printf "#!/bin/sh\\nexit 0\\n" > "$HOME/.local/bin/citronpods-daemon"\n'
            'chmod +x "$HOME/.local/bin/citronpods-daemon"\n'
            'echo "Compiled native M10 engine"\n'
        )
        first = self.boot()
        self.assertEqual(first.returncode, 0, first.stderr)
        status = (self.home / ".local/state/golden-gate/citronpods-engine-status").read_text()
        self.assertIn("installed", status)
        self.assertTrue((self.bin / "citronpods-daemon").exists())
        self.assertIn("Compiled native M10 engine", (self.home / ".local/state/golden-gate/citronpods-build.log").read_text())
        second = self.boot()
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertIn("enable --now citronpods-daemon.service", self.log.read_text())

    def test_service_and_installer_own_no_separate_airpods_application(self):
        src = (ROOT / "scripts/install.sh").read_text()
        pane = (ROOT / "apps/settings/panes/CitronPodsPane.qml").read_text()
        service = (ROOT / "apps/citronpods/citronpods-engine-bootstrap.service").read_text()
        watcher = (ROOT / "apps/citronpods/citronpods-engine-bootstrap.path").read_text()
        self.assertIn('citronpods-engine-bootstrap.service', src)
        self.assertIn('citronpods-engine-bootstrap.path', src)
        self.assertIn('gg-citronpods-bootstrap', src)
        self.assertIn('PathChanged=%h/Downloads', watcher)
        self.assertIn('TimeoutStartSec=300', service)
        self.assertIn('citronpods-engine-status', pane)
        self.assertIn('shadowEnabled: false', (ROOT / "shell/CitronPodsPopup.qml").read_text())
        self.assertNotIn('qt_add_executable(citronpods)', (ROOT / "apps/citronpods/bootstrap.sh").read_text())


if __name__ == "__main__":
    unittest.main(verbosity=2)
