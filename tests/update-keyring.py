#!/usr/bin/env python3
"""Software Update gets past an out-of-date pacman keyring.

A computer installed from an older ISO has older package signing keys than
today's packages need, and pacman refuses them ("signature … is unknown
trust"). The helper updates archlinux-keyring before upgrading and, if pacman
still can't verify a package, rebuilds the keyring and tries once more. A
stand-in pacman fails that way until its keyring has been repaired. Also
checks that a failure Software Update can't repair is explained in words."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "apps/settings/update-helper.py"

PACMAN = r"""#!/bin/sh
echo "pacman $*" >> "$STATE/log"
case "$*" in
  *-Syu*)
    if [ "$MODE" = offline ]; then
      echo "error: failed retrieving file 'core.db' from geo.mirror.pkgbuild.com : Could not resolve host: geo.mirror.pkgbuild.com"
      exit 1
    fi
    if [ -e "$STATE/populated" ] && [ -e "$STATE/keyring-new" ]; then
      echo "(1/1) upgrading mesa"; exit 0
    fi
    echo 'error: mesa: signature from "Jane Packager <jane@archlinux.org>" is unknown trust'
    echo ':: File /var/cache/pacman/pkg/mesa.pkg.tar.zst is corrupted (invalid or corrupted package (PGP signature)).'
    echo 'error: failed to commit transaction (invalid or corrupted package (PGP signature))'
    echo 'Errors occurred, no packages were upgraded.'
    exit 1 ;;
  *archlinux-keyring*)
    [ -e "$STATE/populated" ] && touch "$STATE/keyring-new"
    exit 0 ;;
esac
exit 0
"""
PACMAN_KEY = r"""#!/bin/sh
echo "pacman-key $*" >> "$STATE/log"
case "$*" in *--populate*) touch "$STATE/populated" ;; esac
exit 0
"""


class KeyringRepair(unittest.TestCase):
    def run_apply(self, mode: str):
        work = Path(tempfile.mkdtemp(prefix="gg-keyring-"))
        fake = work / "bin"
        fake.mkdir()
        for name, body in (("pacman", PACMAN), ("pacman-key", PACMAN_KEY),
                           ("pgrep", "#!/bin/sh\nexit 1\n"), ("flatpak", "#!/bin/sh\nexit 0\n"),
                           ("archlinux-keyring-wkd-sync", "#!/bin/sh\nexit 0\n")):
            (fake / name).write_text(body)
            (fake / name).chmod(0o755)
        root = work / "root"
        (root / "etc/pacman.d/gnupg").mkdir(parents=True)
        (root / "etc/pacman.d/gnupg/pubring.kbx").write_text("")
        (root / "usr/share/golden-gate").mkdir(parents=True)
        env = {**os.environ, "PATH": f"{fake}:{os.environ['PATH']}", "STATE": str(work), "MODE": mode,
               "GG_UPDATE_ROOT": str(root), "GG_UPDATE_API": "http://127.0.0.1:9"}
        proc = subprocess.run([sys.executable, str(HELPER), "apply"], capture_output=True, text=True,
                              env=env, timeout=120)
        events = [json.loads(l) for l in proc.stdout.splitlines() if l.startswith("{")]
        log = (work / "log").read_text().splitlines() if (work / "log").exists() else []
        subprocess.run(["rm", "-rf", str(work)])
        return proc.returncode, events, log

    @unittest.skipUnless(os.geteuid() == 0, "the helper installs as root")
    def test_out_of_date_keyring_is_repaired(self):
        code, events, log = self.run_apply("stale-keyring")
        self.assertEqual(code, 0, events)
        self.assertEqual(events[-1]["event"], "done", events)
        self.assertFalse([e for e in events if e["event"] == "error"], events)
        # The keyring package first, a repair after the refusal, then the upgrade again.
        self.assertIn("archlinux-keyring", log[0])
        self.assertIn("pacman-key --populate", log)
        self.assertEqual(sum("-Syu" in l and "archlinux-keyring" not in l for l in log), 2, log)
        self.assertTrue(any("Repairing the package signing keys" in e.get("message", "") for e in events))

    @unittest.skipUnless(os.geteuid() == 0, "the helper installs as root")
    def test_failure_is_explained(self):
        code, events, log = self.run_apply("offline")
        self.assertNotEqual(code, 0)
        self.assertEqual(events[-1]["event"], "error", events)
        self.assertIn("Check the internet connection", events[-1]["message"])
        self.assertNotIn("pacman-key --populate", log)      # not a keyring problem: no repair


if __name__ == "__main__":
    unittest.main(verbosity=2)
