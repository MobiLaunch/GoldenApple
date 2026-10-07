#!/usr/bin/env python3
"""Web's keyring lookups (apps/browser/passwords.py) with secret-tool mocked:
the line break secret-tool ends its output with isn't part of the password,
so a saved login filled and submitted again matches what's saved, while the
rest of a secret (spaces, a trailing backslash) is kept as it is."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("passwords", ROOT / "apps/browser/passwords.py")
passwords = importlib.util.module_from_spec(spec)
spec.loader.exec_module(passwords)


def keyring(stdout):
    def run(cmd, **kw):
        return subprocess.CompletedProcess(cmd, 0, stdout, "")
    return passwords.Passwords("default", runner=run)


class Lookup(unittest.TestCase):
    def test_the_terminator_is_dropped(self):
        self.assertEqual(keyring("correct horse\n").password("https://example.com", "ada"), "correct horse")
        self.assertEqual(keyring("correct horse").password("https://example.com", "ada"), "correct horse")

    def test_the_secret_itself_is_kept(self):
        self.assertEqual(keyring("  spaced  \n").password("https://example.com", "ada"), "  spaced  ")
        self.assertEqual(keyring("ends\\\n").password("https://example.com", "ada"), "ends\\")

    def test_missing(self):
        def run(cmd, **kw):
            return subprocess.CompletedProcess(cmd, 1, "", "")
        self.assertIsNone(passwords.Passwords("default", runner=run).password("https://example.com", "ada"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
