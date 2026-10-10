#!/usr/bin/env python3
"""Helpers give up on a command that never answers, instead of hanging the
app that asked: Mail on a keyring waiting to be unlocked (secret-tool), and
tiling on a compositor that doesn't reply (hyprctl)."""
import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Timeouts(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        for tool in ("secret-tool", "hyprctl"):          # both answer nothing, ever
            (self.bin / tool).write_text("#!/bin/sh\nexec sleep 600\n")
            (self.bin / tool).chmod(0o755)
        self.path = os.environ["PATH"]
        os.environ["PATH"] = f"{self.bin}:{self.path}"

    def tearDown(self):
        os.environ["PATH"] = self.path

    def test_mail_keyring_that_never_answers(self):
        (self.tmp / "golden-gate").mkdir()
        (self.tmp / "golden-gate/mail.json").write_text('{"email": "ada@example.com"}')
        os.environ["XDG_CONFIG_HOME"] = str(self.tmp)
        try:
            mail = load("mail_helper", "apps/mail/helper.py")
        finally:
            os.environ.pop("XDG_CONFIG_HOME")
        mail.KEYRING_WAIT = 1
        start = time.monotonic()
        with self.assertRaisesRegex(RuntimeError, "keyring didn't answer"):
            mail.secret_lookup("ada@example.com")
        with self.assertRaisesRegex(RuntimeError, "keyring didn't answer|could not be saved"):
            mail.secret_store("ada@example.com", "pw")
        self.assertEqual(mail.cmd_status(), 1, "status reports the keyring, not a traceback")
        self.assertLess(time.monotonic() - start, 10)

    def test_tiling_with_a_compositor_that_never_answers(self):
        tile = load("tile", "compositor/hyprland/tile.py")
        start = time.monotonic()
        self.assertEqual(tile.hyprctl("clients", "-j"), "")
        self.assertLess(time.monotonic() - start, 6)


if __name__ == "__main__":
    unittest.main()
