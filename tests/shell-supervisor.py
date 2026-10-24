#!/usr/bin/env python3
"""The line in hyprland.conf that keeps the shell running: on a new account
(no ~/.local/state) the shell still starts, a big log is set aside as .old,
and the shell is started again when it stops."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
LINE = next(l for l in (ROOT / "compositor/hyprland/hyprland.conf").read_text().splitlines()
            if l.startswith("exec-once = sh -c") and "qs -c golden-gate >>" in l)
CMD = LINE.removeprefix("exec-once = ")


class Supervisor(unittest.TestCase):
    def run_for(self, seconds):
        tmp = Path(tempfile.mkdtemp())
        (tmp / "bin").mkdir()
        (tmp / "home").mkdir()
        (tmp / "bin/qs").write_text("#!/bin/sh\necho shell ran\n")         # a shell that stops at once
        (tmp / "bin/logger").write_text("#!/bin/sh\n:\n")
        for f in (tmp / "bin").iterdir():
            f.chmod(0o755)
        self.home = tmp / "home"
        self.log = self.home / ".local/state/golden-gate-shell.log"
        return tmp, lambda: subprocess.run(["timeout", str(seconds), "sh", "-c", CMD],
                                           env=dict(os.environ, HOME=str(self.home), PATH=f"{tmp / 'bin'}:{os.environ['PATH']}"))

    def test_new_account_without_local_state(self):
        _, run = self.run_for(3)
        run()
        self.assertTrue(self.log.exists(), "the shell started, its log made")
        self.assertGreaterEqual(self.log.read_text().count("shell ran"), 2, "and was started again after stopping")

    def test_big_log_is_set_aside(self):
        _, run = self.run_for(1)
        self.log.parent.mkdir(parents=True)
        self.log.write_bytes(b"\0" * 4_100_000)
        run()
        self.assertEqual((self.log.parent / "golden-gate-shell.log.old").stat().st_size, 4_100_000)
        self.assertLess(self.log.stat().st_size, 1000)

    def test_only_positional_names(self):
        # Hyprland replaces $words with its own variables; the script mustn't use any.
        script = CMD.split("'")[1]
        self.assertEqual(re.findall(r"\$[A-Za-z_]\w*", script), [], "use $1, not named shell variables")


if __name__ == "__main__":
    unittest.main()
