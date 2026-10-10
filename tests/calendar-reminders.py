#!/usr/bin/env python3
"""Offline event reminder rule, dedupe, and private-state regressions."""
import datetime as dt
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "apps/calendar"))
spec = importlib.util.spec_from_file_location("calendar_reminders", ROOT / "apps/calendar/reminders.py")
rem = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rem)


def entry(**kw):
    return dict(id="test", title="Appointment", date="2026-10-08", time="12:00",
                calendar="Home", repeat="weekly", reminder=15, **kw)


class ReminderTests(unittest.TestCase):
    def test_offset_and_recurring_identity(self):
        start = dt.datetime(2026, 10, 8, 11, 45)
        first = list(rem.due_notifications([entry()], start))
        self.assertEqual(len(first), 1)
        self.assertEqual(len(first[0][0]), 64)
        self.assertEqual(list(rem.due_notifications([entry()], start + dt.timedelta(minutes=3))), [])
        next_week = list(rem.due_notifications([entry()], dt.datetime(2026, 10, 15, 11, 45)))
        self.assertEqual(len(next_week), 1)
        self.assertNotEqual(first[0][0], next_week[0][0])

    def test_skipped_and_moved_exception(self):
        ev = entry(exceptions={
            "2026-10-15": None,
            "2026-10-22": dict(title="Moved", date="2026-10-23", time="14:00",
                                calendar="Home", reminder=5)})
        self.assertEqual(list(rem.due_notifications([ev], dt.datetime(2026, 10, 15, 11, 45))), [])
        self.assertEqual(list(rem.due_notifications([ev], dt.datetime(2026, 10, 22, 11, 45))), [])
        due = list(rem.due_notifications([ev], dt.datetime(2026, 10, 23, 13, 55)))
        self.assertEqual(len(due), 1)
        self.assertEqual(due[0][1], "Moved")

    def test_all_day_uses_nine_am(self):
        ev = entry()
        ev["time"] = ""
        ev["reminder"] = 0
        self.assertEqual(len(list(rem.due_notifications([ev], dt.datetime(2026, 10, 8, 9, 0)))), 1)
        self.assertEqual(list(rem.due_notifications([ev], dt.datetime(2026, 10, 8, 0, 0))), [])

    def test_history_private_and_damage_preserved(self):
        with tempfile.TemporaryDirectory() as temp:
            saved = rem.STATE
            try:
                rem.STATE = Path(temp) / "sent.json"
                with rem.locked_history():
                    self.assertEqual(rem.read_history(), {})
                    rem.save_history({"hash": 123.0})
                    self.assertEqual(rem.read_history(), {"hash": 123.0})
                self.assertEqual(rem.STATE.stat().st_mode & 0o777, 0o600)
                rem.STATE.write_text("{broken")
                with self.assertRaises(ValueError):
                    rem.read_history()
                self.assertEqual(rem.STATE.read_text(), "{broken")
            finally:
                rem.STATE = saved


if __name__ == "__main__":
    unittest.main(verbosity=2)
