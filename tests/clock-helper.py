#!/usr/bin/env python3
"""Clock's alarms and timer (apps/clock/helper.py) with systemctl and
systemd-run stood in for: an alarm is set only once systemd took it (unit
files with Persistent=true, then listed); one that systemd refuses is
reported and leaves nothing behind; alarms can be listed and deleted; a
one-time alarm removes itself when it goes off, a daily one stays; the
timer's deadline is kept on disk (closing Clock doesn't lose it), pausing
keeps what's left, and a failed start says so.

Failures are transactional: a unit turned on is turned off again when
saving fails; an alarm whose unit won't turn off stays listed; a timer
cancelled while systemd can't stop its unit says so, and that unit's
firing (like any from a cancelled, paused or restarted timer) says
nothing; a timer whose unit was lost with the user's service manager is
set again."""
from __future__ import annotations

import json
import os
import re
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
        self.tool("systemctl", 'echo "systemctl $*" >> "$LOG"\n'
                  '[ -n "$FAIL_SYSTEMCTL" ] && case "$*" in *enable*) echo "Failed to connect to bus: No medium found" >&2; exit 1;; esac\n'
                  '[ -n "$FAIL_STOP" ] && case "$*" in *" stop "*|*disable*) echo "Access denied" >&2; exit 1;; esac\n'
                  '[ -n "$INACTIVE" ] && case "$*" in *is-active*) echo inactive; exit 3;; esac\n'
                  'case "$*" in *enable*) [ -n "$SABOTAGE" ] && mkdir -p "$SABOTAGE";; esac\nexit 0')
        self.tool("systemd-run", 'echo "systemd-run $*" >> "$LOG"; [ -n "$FAIL_RUN" ] && { echo "Failed to connect to bus" >&2; exit 1; }\n'
                  '[ -n "$SABOTAGE" ] && mkdir -p "$SABOTAGE"; exit 0')
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


    # A save that fails after systemd took the unit: clock.json can't be
    # replaced (a directory is where it goes), as on a full or read-only disk.
    def clock_json(self):
        return str(self.base / "data/golden-gate/clock.json")

    def test_alarm_that_cant_be_saved_is_turned_off_again(self):
        r = self.helper("alarm-add", "07:30", "Wake up", SABOTAGE=self.clock_json())
        self.assertFalse(r["ok"], r)
        self.assertIn("couldn't be saved", r["error"])
        self.assertEqual(self.units(), [], "nothing left on that Clock doesn't list")
        self.assertIn("disable --now", self.log.read_text())

    def test_timer_that_cant_be_saved_is_stopped_again(self):
        r = self.helper("timer-start", "60", SABOTAGE=self.clock_json())
        self.assertFalse(r["ok"], r)
        self.assertIn("couldn't be saved", r["error"])
        started = re.search(r"--unit=(gg-clock-timer-\w+)", self.log.read_text()).group(1)
        self.assertIn(f"systemctl --user stop {started}.timer", self.log.read_text())

    def test_alarm_whose_unit_wont_turn_off_stays(self):
        aid = self.helper("alarm-add", "07:30", "Wake up")["alarm"]["id"]
        r = self.helper("alarm-remove", aid, FAIL_STOP="1")
        self.assertFalse(r["ok"])
        self.assertIn("Access denied", r["error"])
        self.assertEqual([a["id"] for a in self.helper("status")["alarms"]], [aid], "still listed: it can still go off")

    def fire_timer(self, gen):
        subprocess.run([sys.executable, str(HELPER), "fire-timer", gen], env=self.env, check=True)

    def gen(self):
        return self.helper("status")["timer"]["gen"]

    def notified(self):
        return self.log.read_text().count("notify-send") if self.log.exists() else 0

    def test_cancel_systemd_cant_stop_says_so_and_stays_quiet(self):
        self.helper("timer-start", "1")
        gen = self.gen()
        r = self.helper("timer-cancel", FAIL_STOP="1")
        self.assertTrue(r["ok"], r)
        self.assertIn("Access denied", r["note"], "the leftover is reported, not hidden")
        self.assertEqual(self.helper("status")["timer"], {})
        time.sleep(1.1)
        self.fire_timer(gen)                     # the unit that couldn't be stopped goes off
        self.assertEqual(self.notified(), 0)
        self.assertEqual(self.helper("status")["timer"], {}, "no finished timer brought back")

    def test_cancel_twice(self):
        self.helper("timer-start", "60")
        self.assertTrue(self.helper("timer-cancel")["ok"])
        r = self.helper("timer-cancel")
        self.assertTrue(r["ok"])
        self.assertNotIn("note", r)

    def test_a_restarted_timers_old_firing_says_nothing(self):
        self.helper("timer-start", "1")
        old = self.gen()
        self.helper("timer-start", "600")
        new = self.gen()
        self.assertNotEqual(old, new)
        self.assertIn(f"stop gg-clock-timer-{old}.timer", self.log.read_text(), "the old unit is stopped")
        time.sleep(1.1)
        self.fire_timer(old)
        self.assertEqual(self.notified(), 0)
        self.assertIn("deadline", self.helper("status")["timer"], "the new timer still runs")

    def test_paused_timers_firing_says_nothing(self):
        self.helper("timer-start", "1")
        gen = self.gen()
        self.helper("timer-pause")
        time.sleep(1.1)
        self.fire_timer(gen)
        self.assertEqual(self.notified(), 0)

    def test_the_running_timer_goes_off(self):
        self.helper("timer-start", "1")
        gen = self.gen()
        time.sleep(1.1)
        self.fire_timer(gen)
        self.assertEqual(self.notified(), 1)
        self.assertIn("finished", self.helper("status")["timer"])

    def test_timer_lost_with_the_service_manager_is_set_again(self):
        self.helper("timer-start", "300")
        gen = self.gen()
        self.log.write_text("")
        t = self.helper("status", INACTIVE="1")
        self.assertNotIn("note", t)
        self.assertIn(f"--unit=gg-clock-timer-{gen}", self.log.read_text())
        self.assertIn(f"fire-timer {gen}", self.log.read_text(), "with the same generation")


if __name__ == "__main__":
    unittest.main(verbosity=2)
