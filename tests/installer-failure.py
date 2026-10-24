#!/usr/bin/env python3
"""How the installer backend (apps/installer/helper.py) fails, with every
command mocked: it refuses a disk that isn't the one confirmed (another put
in its place) before erasing anything; once it has erased, an error says so
(erased, the stage it was in, where the log is) so the window can show a
partial install rather than the normal confirmation page; it carries on if
its window goes away; and closing, hang-ups and plain kills don't stop it."""
from __future__ import annotations

import importlib.util
import io
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("installer_failure", ROOT / "apps/installer/helper.py")
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)

DISK = {"model": "Samsung SSD", "serial": "S5GX123", "size": 512110190592}


class Failing(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        installer.LOG = Path(self.tmp.name) / "install.log"
        self.signals = {s: signal.getsignal(s) for s in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM, signal.SIGPIPE)}

    def tearDown(self):
        for s, h in self.signals.items():
            signal.signal(s, h)
        self.tmp.cleanup()

    def install(self, disk_now=DISK, fail=None, identity=None):
        identity = installer.identity(DISK) if identity is None else identity
        """Run install() with the commands mocked; `fail` names the one that fails."""
        ran = []

        def run(args, *, input_text=None, check=True):
            ran.append(args[0] if args[0] != "arch-chroot" else args[2])
            if args[0] == "lsblk" and "TYPE,RO,SIZE" in args:
                return subprocess.CompletedProcess(args, 0, "disk 0 512110190592\n", "")
            if args[0] == "lsblk" and "MODEL,SERIAL,SIZE" in args:
                return subprocess.CompletedProcess(args, 0, json.dumps({"blockdevices": [disk_now]}), "")
            if ran[-1] == fail:
                raise subprocess.CalledProcessError(1, args, "mkfs.ext4: Device size reported to be zero\n")
            return subprocess.CompletedProcess(args, 0, "", "")

        payload = {"device": "/dev/sda", "username": "grace", "password": "correct-horse",
                   "confirm": "ERASE:/dev/sda", "identity": identity}
        real_is_dir, real_exists = Path.is_dir, Path.exists
        out = io.StringIO()
        with patch.object(installer, "run", run), \
                patch.object(installer, "taken_names", return_value=set()), \
                patch.object(installer.os, "geteuid", return_value=0), \
                patch.object(installer, "live_device", return_value="/dev/sdb"), \
                patch.object(installer, "release_device", lambda d: None), \
                patch.object(installer, "wait_for_partitions", lambda *a, **k: None), \
                patch.object(installer.subprocess, "run", lambda *a, **k: ran.append(a[0][0])), \
                patch.object(installer.pathlib.Path, "mkdir", lambda *a, **k: None), \
                patch.object(installer.pathlib.Path, "is_dir", lambda p: True if str(p).startswith(("/run/archiso", "/sys/firmware")) else real_is_dir(p)), \
                patch.object(installer.pathlib.Path, "exists", lambda p: True if str(p) in ("/dev/sda", "/sys/firmware/efi") else real_exists(p)), \
                patch.object(installer.sys, "stdin", io.StringIO(json.dumps(payload))), \
                patch.object(installer.sys, "stdout", out):
            code = installer.install()
        events = [json.loads(line) for line in out.getvalue().splitlines() if line.startswith("{")]
        return code, events, ran

    def test_a_different_disk_is_refused_before_erasing(self):
        code, events, ran = self.install(disk_now=dict(DISK, serial="OTHER999"))
        self.assertEqual(code, 1)
        self.assertIn("isn't the one you chose", events[-1]["message"])
        self.assertFalse(events[-1]["erased"])
        self.assertNotIn("wipefs", ran)
        self.assertNotIn("erasing", [e["event"] for e in events])

    def test_no_identity_is_refused(self):
        code, events, ran = self.install(identity="")
        self.assertEqual(code, 1)
        self.assertNotIn("wipefs", ran)

    def test_a_failure_after_erasing_says_so(self):
        code, events, ran = self.install(fail="mkfs.ext4")
        self.assertEqual(code, 1)
        self.assertIn("wipefs", ran)
        kinds = [e["event"] for e in events]
        self.assertLess(kinds.index("erasing"), len(kinds) - 1)
        err = events[-1]
        self.assertEqual(err["event"], "error")
        self.assertTrue(err["erased"])
        self.assertEqual(err["stage"], "Creating filesystems")
        self.assertIn("Device size reported to be zero", err["message"])
        self.assertEqual(err["log"], str(installer.LOG))
        self.assertIn('"event":"error"', installer.LOG.read_text(), "the log has it too")

    def test_closing_the_window_doesnt_stop_it(self):
        self.install(fail="mkfs.ext4")
        for s in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
            self.assertEqual(signal.getsignal(s), signal.SIG_IGN, s)
        # Its window gone: events still go to the log, nothing raises.
        with patch.object(installer.sys, "stdout", open(os.devnull, "w")) as gone:
            gone.close()
            installer.emit("progress", message="still going")
        self.assertIn("still going", installer.LOG.read_text())

    def test_disks_carry_their_identity(self):
        def run(args, *, input_text=None, check=True):
            return subprocess.CompletedProcess(args, 0, json.dumps({"blockdevices": [
                dict(DISK, path="/dev/sda", type="disk", tran="nvme", rm=False, ro=False)]}), "")
        out = io.StringIO()
        with patch.object(installer, "run", run), patch.object(installer, "live_device", return_value=""), \
                patch.object(installer.sys, "stdout", out):
            installer.disks()
        self.assertEqual(json.loads(out.getvalue())[0]["identity"], "Samsung SSD|S5GX123|512110190592")


if __name__ == "__main__":
    unittest.main(verbosity=2)
