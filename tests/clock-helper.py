#!/usr/bin/env python3
"""Clock's alarms and timer (apps/clock/helper.py) with systemctl and
systemd-run stood in for: an alarm is set only once systemd took it (unit
files with Persistent=true, then listed); one that systemd refuses is
reported and leaves nothing behind; alarms can be listed and deleted; a
one-time alarm removes itself when it goes off, a daily one stays; the
timer's deadline is kept on disk (closing Clock doesn't lose it), pausing
keeps what's left, and a failed start says so."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

HELPER = Path(__file__).resolve().parents[1] / "apps/clock/helper.py"


class Clock(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.log = self.base / "log"
        self.tool("systemctl", 'echo "systemctl $*" >> "$LOG"; [ -n "$FAIL_SYSTEMCTL" ] && case "$*" in *enable*) echo "Failed to connect to bus: No medium found" >&2; exit 1;; esac; exit 0')
        self.tool("systemd-run", 'echo "systemd-run $*" >> "$LOG"; [ -n "$FAIL_RUN" ] && { echo "Failed to connect to bus" >&2; exit 1; }; exit 0')
        self.tool("notify-send", 'echo "notify-send $*" >> "$LOG"')
        self.env = {**os.environ, "PATH": f"{self.bin}:{os.environ['PATH']}", "LOG": str(self.log),
                    "XDG_CONFIG_HOME": str(self.base / "config"), "XDG_DATA_HOME": str(self.base / "data")}

    def tearDown(self):
        self.tmp.cleanup()

    def tool(self, name, body):
        (self.bin / name).write_text("#!/bin/sh\n" + body + "\n")
        (self.bin / name).chmod(0o755)

    def helper(self, *args, **env):
        p = subprocess.run([sys.executable, str(HELPER), *args], capture_output=True, text=True, env={**self.env, **env})
        return json.loads(p.stdout) if p.stdout.strip() else {"code": p.returncode}

    def units(self):
        d = self.base / "config/systemd/user"
        return sorted(p.name for p in d.iterdir()) if d.exists() else []

    def test_alarm_set_listed_and_deleted(self):
        r = self.helper("alarm-add", "07:30", "Wake up", "daily")
        self.assertTrue(r["ok"], r)
        aid = r["alarm"]["id"]
        self.assertEqual(self.units(), [f"gg-alarm-{aid}.service", f"gg-alarm-{aid}.timer"])
        timer = (self.base / f"config/systemd/user/gg-alarm-{aid}.timer").read_text()
        self.assertIn("OnCalendar=*-*-* 07:30:00", timer)
        self.assertIn("Persistent=true", timer)
        self.assertIn(f"systemctl --user enable --now gg-alarm-{aid}.timer", self.log.read_text())
        self.assertEqual([a["name"] for a in self.helper("status")["alarms"]], ["Wake up"])
        self.assertTrue(self.helper("alarm-remove", aid)["ok"])
        self.assertEqual(self.units(), [])
        self.assertEqual(self.helper("status")["alarms"], [])

    def test_refused_alarm_is_reported_and_leaves_nothing(self):
        r = self.helper("alarm-add", "07:30", "Wake up", FAIL_SYSTEMCTL="1")
        self.assertFalse(r["ok"])
        self.assertIn("No medium found", r["error"])
        self.assertEqual(self.units(), [])
        self.assertEqual(self.helper("status")["alarms"], [])

    def test_bad_time(self):
        for t in ("7:30", "24:00", "noon"):
            self.assertFalse(self.helper("alarm-add", t, "x")["ok"], t)

    def test_one_time_alarm_goes_once_daily_stays(self):
        once = self.helper("alarm-add", "06:00", "Flight")["alarm"]["id"]
        daily = self.helper("alarm-add", "08:00", "Standup", "daily")["alarm"]["id"]
        once_timer = (self.base / f"config/systemd/user/gg-alarm-{once}.timer").read_text()
        self.assertRegex(once_timer, r"OnCalendar=\d{4}-\d\d-\d\d 06:00:00")
        subprocess.run([sys.executable, str(HELPER), "fire", once], env=self.env, check=True)
        subprocess.run([sys.executable, str(HELPER), "fire", daily], env=self.env, check=True)
        self.assertIn("notify-send", self.log.read_text())
        self.assertEqual([a["id"] for a in self.helper("status")["alarms"]], [daily])
        self.assertEqual(self.units(), [f"gg-alarm-{daily}.service", f"gg-alarm-{daily}.timer"])

    def test_timer_outlives_the_window(self):
        r = self.helper("timer-start", "300")
        self.assertTrue(r["ok"], r)
        self.assertIn("--unit=gg-clock-timer", self.log.read_text())
        self.assertIn("--on-calendar=", self.log.read_text(), "wall-clock time: sleep counts")
        # Clock closed and opened again: the deadline is still there.
        t = self.helper("status")["timer"]
        self.assertAlmostEqual(t["deadline"], time.time() + 300, delta=5)
        paused = self.helper("timer-pause")["timer"]
        self.assertIn(paused["remaining"], range(295, 301))
        self.assertNotIn("deadline", self.helper("status")["timer"])
        self.assertTrue(self.helper("timer-start", str(paused["remaining"]))["ok"])
        self.assertEqual(self.helper("status")["timer"]["seconds"], 300, "the length it was set for")
        self.assertTrue(self.helper("timer-cancel")["ok"])
        self.assertEqual(self.helper("status")["timer"], {})

    def test_timer_that_cant_start(self):
        r = self.helper("timer-start", "60", FAIL_RUN="1")
        self.assertFalse(r["ok"])
        self.assertIn("didn't start", r["error"])
        self.assertEqual(self.helper("status")["timer"], {})


if __name__ == "__main__":
    unittest.main(verbosity=2)
