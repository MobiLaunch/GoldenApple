#!/usr/bin/env python3
"""Web's keyring lookups (apps/browser/passwords.py) with secret-tool mocked:
the line break secret-tool ends its output with isn't part of the password,
so a saved login filled and submitted again matches what's saved, while the
rest of a secret (spaces, a trailing backslash) is kept as it is. And the
keyring is reached in the background: a keyring that takes its time (as
a locked one does) never holds up the window, says it's waiting, and a
site's logins are looked up once and cached."""
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


class Background(unittest.TestCase):
    def test_a_slow_keyring_never_blocks(self):
        import os, sys, tempfile, time, json
        os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
        sys.path.insert(0, str(ROOT / "apps/browser"))
        from PySide6.QtGui import QGuiApplication
        from PySide6.QtTest import QTest
        app = QGuiApplication.instance() or QGuiApplication([])
        import backend
        tmp = Path(tempfile.mkdtemp())
        web = backend.BrowserBackend(data_dir=tmp / "d", cache_dir=tmp / "c", download_dir=tmp / "dl")
        calls = []

        def slow(cmd, **kw):
            calls.append(cmd[1])
            time.sleep(0.6)
            if cmd[1] == "search":
                return subprocess.CompletedProcess(cmd, 0, "", "attribute.app = org.goldengate.Web\n"
                    "attribute.profile = " + web.passwords.profile + "\nattribute.origin = https://example.com\n"
                    "attribute.username = ada\n")
            return subprocess.CompletedProcess(cmd, 0, "correct horse\n", "")
        web.passwords._run = slow
        web.CACHE_SECONDS = 60
        got = []
        web.passwordOfferReady.connect(lambda req, kind: got.append((req, kind)))
        scripts = []
        web.passwordScriptReady.connect(lambda req, script: scripts.append(req))
        started = time.monotonic()
        web.requestPasswordOffer("a", "https://example.com/login", "ada", "correct horse")
        web.requestPasswordOffer("b", "https://example.com/login", "ada", "new horse")
        web.requestPasswordScript("p", "https://example.com/")
        self.assertLess(time.monotonic() - started, 0.2, "the window isn't held up")
        for _ in range(100):
            QTest.qWait(50)
            if web.keyringWaiting:
                break
        self.assertTrue(web.keyringWaiting, "it says it's waiting for the keyring")
        for _ in range(100):
            QTest.qWait(50)
            if len(got) == 2 and scripts and not web.keyringWaiting:
                break
        self.assertEqual(sorted(got), [("a", ""), ("b", "update")], "unchanged, then changed")
        self.assertEqual(scripts, ["p"])
        self.assertEqual(calls.count("lookup"), 1, "one lookup, then the cache")
        self.assertFalse(web.keyringWaiting)


if __name__ == "__main__":
    unittest.main(verbosity=2)
