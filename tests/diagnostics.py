#!/usr/bin/env python3
"""Exercise report generation with real launch logs in an isolated home."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class Diagnostics(unittest.TestCase):
    def report(self, populate=None, custom_cache=False):
        with tempfile.TemporaryDirectory() as directory:
            tmp = Path(directory)
            home = tmp / "home"
            home.mkdir()
            cache = tmp / "custom cache" if custom_cache else home / ".cache"
            logs = cache / "golden-gate/mac-logs"
            logs.mkdir(parents=True)
            if populate:
                populate(logs)
            bin_dir = tmp / "bin"
            bin_dir.mkdir()
            # Avoid contacting the current session or opening an application.
            for name in ("xdg-open", "journalctl", "coredumpctl", "systemctl",
                         "busctl", "hyprctl", "qs", "flatpak", "pgrep",
                         "pacman", "systemd-detect-virt"):
                body = 'exit 0\n'
                if name == "pacman":
                    body = 'echo "darling-bin test-release"\n'
                (bin_dir / name).write_text("#!/bin/sh\n" + body)
                (bin_dir / name).chmod(0o755)
            (bin_dir / "xdg-user-dir").write_text('#!/bin/sh\nprintf "%s\\n" "$HOME/Documents"\n')
            (bin_dir / "xdg-user-dir").chmod(0o755)
            (bin_dir / "darling").write_text(f'#!/bin/sh\ntouch "{tmp}/darling-invoked"\n')
            (bin_dir / "darling").chmod(0o755)
            env = {**os.environ, "HOME": str(home), "XDG_RUNTIME_DIR": str(tmp / "runtime"),
                   "PATH": f"{bin_dir}:{os.environ['PATH']}"}
            env.pop("XDG_CACHE_HOME", None)
            if custom_cache:
                env["XDG_CACHE_HOME"] = str(cache)
            result = subprocess.run(["bash", str(ROOT / "apps/setup/diagnostics.sh"),
                                     "--crash", "mldr"], env=env, capture_output=True,
                                    text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse((tmp / "darling-invoked").exists())
            return Path(result.stdout.strip()).read_text()

    def test_missing_logs(self):
        self.assertIn("No Mac app launch logs recorded.", self.report())

    def test_preserves_loader_reason_and_bounds_output(self):
        def populate(logs):
            (logs / "iina.log").write_text(
                "Library not loaded: /System/Library/PrivateFrameworks/PIP.framework/Versions/A/PIP\n"
                + "shutdown noise\n" * 100000 + "abort_with_payload: image not found\n")
            (logs / "install-iina.log").write_text("INSTALL OUTPUT MUST NOT APPEAR\n")
            (logs / "linked.log").symlink_to(logs / "install-iina.log")
            (logs.parent / "darling-setup.log").write_text("Setup failed: example\n")
        report = self.report(populate, custom_cache=True)
        self.assertIn("Library not loaded: /System/Library/PrivateFrameworks/PIP.framework", report)
        self.assertIn("abort_with_payload: image not found", report)
        self.assertIn("Setup failed: example", report)
        self.assertIn("darling-bin test-release", report)
        self.assertNotIn("INSTALL OUTPUT MUST NOT APPEAR", report)
        self.assertLess(len(report), 30000)

    def test_only_latest_five_launches(self):
        def populate(logs):
            for i in range(7):
                p = logs / f"app{i}.log"
                p.write_text(f"UNIQUE LAUNCH {i}\n")
                os.utime(p, (i + 1, i + 1))
        report = self.report(populate)
        self.assertNotIn("UNIQUE LAUNCH 0", report)
        self.assertNotIn("UNIQUE LAUNCH 1", report)
        for i in range(2, 7):
            self.assertIn(f"UNIQUE LAUNCH {i}", report)


if __name__ == "__main__":
    unittest.main()
