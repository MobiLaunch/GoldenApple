#!/usr/bin/env python3
"""The installer's account checks (apps/installer/helper.py with
apps/setup/account_rules.py, which Hello shares): a name the installed system
already has (root, or any account or group in the image being copied) or a
password that's short or holds a line break is refused on the account page
and again by the install itself, before the disk is touched. Every command
is mocked; nothing here can erase anything."""
from __future__ import annotations

import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


installer = module("installer_helper", "apps/installer/helper.py")
account = module("account_helper", "apps/setup/account-helper.py")


class Rules(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.image = Path(self.tmp.name)
        (self.image / "etc").mkdir()
        (self.image / "etc/passwd").write_text("root:x:0:0::/root:/bin/bash\ngolden:x:1000:1000::/home/golden:/bin/bash\n"
                                               "ada:x:1001:1001::/home/ada:/bin/bash\n")
        (self.image / "etc/group").write_text("root:x:0:\nwheel:x:998:golden\nlpadmin:x:997:\n")

    def tearDown(self):
        self.tmp.cleanup()

    def problem(self, username, password="correct-horse"):
        return installer.account_problem({"username": username, "password": password}, str(self.image))

    def test_names(self):
        self.assertEqual(self.problem("grace"), "")
        self.assertEqual(self.problem("golden"), "", "the live account is removed before yours is made")
        for name in ("root", "ada", "wheel", "lpadmin", "nobody", "sddm"):
            self.assertIn("already used", self.problem(name), name)
        for name in ("Grace", "1grace", "", "a" * 32, "grace smith"):
            self.assertIn("lowercase", self.problem(name), name)

    def test_passwords(self):
        for pw in ("short", "1234567", "line\nbreak!", "carriage\rreturn", "nul\0char!!", "bell\x07char!!", "x" * 257, None, 12345678):
            self.assertNotEqual(self.problem("grace", pw), "", repr(pw))
        self.assertEqual(self.problem("grace", "eight ch"), "")

    def test_hello_uses_the_same_rules(self):
        for bad in ({"password": "1234567"}, {"password": "two\nlines!!"}, {"username": "root"}):
            with self.assertRaises(ValueError):
                account.validate({"username": "grace", "fullName": "Grace Hopper", "password": "correct-horse", **bad})
        self.assertEqual(account.validate({"username": "grace", "fullName": " Grace ", "password": "correct-horse"}),
                         ("grace", "Grace", "correct-horse"))

    def test_account_page_check(self):
        for payload, ok in (({"username": "grace", "password": "correct-horse"}, True),
                            ({"username": "root", "password": "correct-horse"}, False),
                            ({"username": "grace", "password": "a\nb\nc\nd\ne"}, False)):
            p = subprocess.run([sys.executable, str(ROOT / "apps/installer/helper.py"), "check-account"],
                               input=json.dumps(payload), capture_output=True, text=True)
            self.assertEqual(json.loads(p.stdout)["ok"], ok, payload)


class NothingErasedFirst(unittest.TestCase):
    def test_bad_account_stops_the_install_before_the_disk(self):
        calls = []

        def run(args, *, input_text=None, check=True):
            calls.append(args)
            if args[0] == "lsblk":
                return subprocess.CompletedProcess(args, 0, "disk 0 128000000000\n", "")
            return subprocess.CompletedProcess(args, 0, "", "")

        payload = {"device": "/dev/sda", "username": "root", "password": "correct-horse", "confirm": "ERASE:/dev/sda"}
        real_is_dir, real_exists = Path.is_dir, Path.exists
        with patch.object(installer, "run", run), \
                patch.object(installer.os, "geteuid", return_value=0), \
                patch.object(installer, "live_device", return_value="/dev/sdb"), \
                patch.object(installer.subprocess, "run", lambda *a, **k: calls.append(a[0])), \
                patch.object(installer.pathlib.Path, "is_dir", lambda p: True if str(p).startswith(("/run/archiso", "/sys/firmware")) else real_is_dir(p)), \
                patch.object(installer.pathlib.Path, "exists", lambda p: True if str(p) in ("/dev/sda", "/sys/firmware/efi") else real_exists(p)), \
                patch.object(installer.sys, "stdin", io.StringIO(json.dumps(payload))), \
                patch("builtins.print") as printed:
            self.assertEqual(installer.install(), 1)
        said = " ".join(str(c.args[0]) for c in printed.call_args_list)
        self.assertIn("already used", said)
        ran = [c[0] for c in calls if c]
        for tool in ("wipefs", "sgdisk", "mkfs.ext4", "mkfs.fat", "rsync", "useradd", "chpasswd"):
            self.assertNotIn(tool, ran, tool + " never ran")


if __name__ == "__main__":
    unittest.main(verbosity=2)
