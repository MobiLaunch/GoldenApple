#!/usr/bin/env python3
"""Calendar's store (apps/calendar/helper.py): a missing store is an empty
calendar, a damaged one is reported and never written over (until Restore
puts the last good copy back, keeping the damaged file); two adds at once
both keep their events; a copy Restore would put back must pass the same
check as the store, or nothing is changed; each restore keeps its own copy
of the damaged file; dates and times are checked for real, and a record
that isn't valid is kept in the file rather than silently dropped."""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor

HELPER = Path(__file__).resolve().parents[1] / "apps/calendar/helper.py"


class CalendarStore(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.data = Path(self.tmp.name)
        self.store = self.data / "golden-gate/calendar/events.json"

    def tearDown(self):
        self.tmp.cleanup()

    def helper(self, *args, event=None):
        p = subprocess.run([sys.executable, str(HELPER), *args], input=json.dumps(event) if event is not None else "",
                           capture_output=True, text=True, env={**os.environ, "XDG_DATA_HOME": str(self.data)})
        return json.loads(p.stdout)

    def add(self, title, date="2026-10-07", time="", calendar="Home", repeat="never", until=""):
        return self.helper("add", event={"title": title, "date": date, "time": time, "calendar": calendar,
                                         "repeat": repeat, "until": until})

    def test_missing_is_empty(self):
        self.assertEqual(self.helper("list"), {"ok": True, "events": [], "invalid": 0})
        self.assertTrue(self.add("Dentist", time="09:30")["ok"])
        self.assertEqual([e["title"] for e in self.helper("list")["events"]], ["Dentist"])

    def test_damaged_store_is_never_written_over(self):
        self.assertTrue(self.add("Kept")["ok"])
        self.assertTrue(self.add("Also kept")["ok"])         # leaves a backup with "Kept"
        self.store.write_text('[{"title": "half')
        r = self.helper("list")
        self.assertFalse(r["ok"])
        self.assertTrue(r["broken"] and r["canRestore"])
        self.assertIn("damaged", r["error"])
        self.assertFalse(self.add("New")["ok"], "an add can't replace it")
        self.assertFalse(self.helper("delete", "x")["ok"])
        self.assertEqual(self.store.read_text(), '[{"title": "half', "left exactly as it was")
        r = self.helper("restore")
        self.assertTrue(r["ok"] and r["restored"])
        self.assertEqual(Path(r["kept"]).read_text(), '[{"title": "half', "the damaged file is kept")
        self.assertEqual([e["title"] for e in self.helper("list")["events"]], ["Kept"])

    def test_wrong_shape_is_damaged_too(self):
        self.store.parent.mkdir(parents=True)
        self.store.write_text('{"events": []}')
        r = self.helper("list")
        self.assertTrue(r["broken"])
        self.assertFalse(r["canRestore"])
        self.assertFalse(self.helper("restore")["ok"])

    def damage_with_backup(self, backup):
        self.store.parent.mkdir(parents=True, exist_ok=True)
        self.store.write_text('[{"title": "half')
        bak = self.store.with_name("events.json.bak")
        if isinstance(backup, bytes):
            bak.write_bytes(backup)
        else:
            bak.mkdir()                          # there, but unreadable as a file
        return bak

    def test_an_unusable_backup_is_not_put_back(self):
        for name, backup in (("object", b'{"events": []}'), ("scalar", b"42"), ("malformed", b"[{"),
                             ("not utf-8", b'["\xff"]'), ("unreadable", None)):
            with self.subTest(name):
                self.setUp()
                self.damage_with_backup(backup)
                r = self.helper("restore")
                self.assertFalse(r["ok"], r)
                self.assertFalse(r.get("restored"))
                self.assertEqual(self.store.read_text(), '[{"title": "half', "the store is left as it was")
                self.assertEqual(list(self.store.parent.glob("events.broken-*")), [], "nothing moved aside")
                self.assertTrue(self.helper("list")["broken"])

    def test_a_restored_store_loads(self):
        self.damage_with_backup(b'[{"id": "a", "title": "Kept", "date": "2026-10-07"}, {"title": ""}]\n')
        r = self.helper("restore")
        self.assertTrue(r["ok"] and r["restored"], r)
        listed = self.helper("list")
        self.assertTrue(listed["ok"])
        self.assertEqual(([e["title"] for e in listed["events"]], listed["invalid"]), (["Kept"], 1),
                         "an invalid record comes back too, not dropped")

    def test_repeated_restores_keep_each_damaged_copy(self):
        self.damage_with_backup(b"[]")
        first = self.helper("restore")["kept"]
        self.store.write_text("[{second")
        second = self.helper("restore")["kept"]
        self.assertNotEqual(first, second, "the same second, two names")
        self.assertEqual((Path(first).read_text(), Path(second).read_text()), ('[{"title": "half', "[{second"))

    def test_concurrent_adds_keep_every_event(self):
        titles = [f"Event {i}" for i in range(12)]
        with ThreadPoolExecutor(12) as pool:
            results = list(pool.map(self.add, titles))
        self.assertTrue(all(r["ok"] for r in results))
        self.assertEqual(sorted(e["title"] for e in self.helper("list")["events"]), sorted(titles))

    def test_add_and_delete_at_once(self):
        first = self.add("Stay")["event"]["id"]
        gone = self.add("Go")["event"]["id"]
        with ThreadPoolExecutor(4) as pool:
            jobs = [pool.submit(self.helper, "delete", gone), pool.submit(self.add, "New 1"), pool.submit(self.add, "New 2")]
            self.assertTrue(all(j.result()["ok"] for j in jobs))
        events = self.helper("list")["events"]
        self.assertEqual(sorted(e["title"] for e in events), ["New 1", "New 2", "Stay"])
        self.assertIn(first, [e["id"] for e in events])

    def test_dates_and_times_are_real(self):
        for date in ("2026-02-30", "2026-13-01", "2026/10/07", "tomorrow!!", ""):
            self.assertFalse(self.add("X", date=date)["ok"], date)
        for time in ("25:00", "9:30", "noon", "12:60", "14:30:00"):
            r = self.add("X", time=time)
            self.assertFalse(r["ok"], time)
            self.assertIn("HH:MM", r["error"])
        self.assertTrue(self.add("Leap day", date="2028-02-29", time="23:59")["ok"])
        self.assertFalse(self.add("  ")["ok"])
        self.assertFalse(self.helper("add", event=["not", "a", "record"])["ok"])

    def test_invalid_records_are_kept_not_dropped(self):
        self.store.parent.mkdir(parents=True)
        bad = {"id": "bad", "title": "Bad", "date": "2026-02-30", "time": "", "calendar": "Home"}
        self.store.write_text(json.dumps([bad]))
        r = self.helper("list")
        self.assertEqual((r["events"], r["invalid"]), ([], 1))
        self.assertTrue(self.add("Good")["ok"])
        stored = json.loads(self.store.read_text())
        self.assertIn(bad, stored, "still in the file after a save")


    def test_edit_reorders_and_preserves_identity(self):
        old = self.add("Review", time="09:15")["event"]
        other = self.add("Unchanged", date="2026-10-08")["event"]
        edited = {"title": "Review updated", "date": "2026-10-09",
                  "time": "17:20", "calendar": "Work", "expected": old}
        response = self.helper("edit", old["id"], event=edited)
        self.assertTrue(response["ok"], response)
        self.assertEqual(response["event"]["id"], old["id"])
        rows = self.helper("list")["events"]
        self.assertEqual([e["title"] for e in rows], ["Unchanged", "Review updated"])
        self.assertIn(other, rows)
        self.assertEqual(rows[1]["calendar"], "Work")

    def test_edit_refuses_stale_and_invalid_changes(self):
        old = self.add("Before")["event"]
        first = {"title": "First", "date": old["date"], "time": "",
                 "calendar": "Home", "expected": old}
        self.assertTrue(self.helper("edit", old["id"], event=first)["ok"])
        second = dict(first, title="Second")
        stale = self.helper("edit", old["id"], event=second)
        self.assertFalse(stale["ok"])
        self.assertTrue(stale["conflict"])
        self.assertFalse(self.helper("edit", old["id"], event=dict(first, expected={}))["ok"])
        self.assertFalse(self.helper("edit", "missing", event=dict(first, expected={"id": "missing"}))["ok"])
        self.assertFalse(self.helper("edit", old["id"], event=dict(first, date="2026-02-30"))["ok"])
        self.assertEqual([r["title"] for r in self.helper("list")["events"]], ["First"])

    def test_duplicate_gets_own_identity_and_can_be_edited(self):
        old = self.add("Dentist", time="09:00")["event"]
        new = self.helper("duplicate", old["id"])
        self.assertTrue(new["ok"], new)
        copy = new["event"]
        self.assertNotEqual(copy["id"], old["id"])
        self.assertEqual(copy["title"], "Copy of Dentist")
        self.assertEqual((copy["date"], copy["time"]), (old["date"], old["time"]))
        self.assertTrue(self.helper("edit", copy["id"], event={
            "expected": copy, "title": "Second visit", "date": copy["date"],
            "time": copy["time"], "calendar": copy["calendar"]})["ok"])
        self.assertEqual(set(r["title"] for r in self.helper("list")["events"]),
                         {"Dentist", "Second visit"})
        self.assertFalse(self.helper("duplicate", "missing")["ok"])

    def test_edit_and_duplicate_do_not_replace_damaged_store(self):
        old = self.add("Kept")["event"]
        self.store.write_text("[broken")
        payload = {**old, "expected": old, "title": "Changed"}
        self.assertTrue(self.helper("edit", old["id"], event=payload)["broken"])
        self.assertTrue(self.helper("duplicate", old["id"])["broken"])
        self.assertEqual(self.store.read_text(), "[broken")

    def test_recurrence_validation_and_backward_compatibility(self):
        for repeat in ("never", "daily", "weekly", "monthly", "yearly"):
            self.assertTrue(self.add("Accepted", repeat=repeat)["ok"], repeat)
        for repeat in ("sometimes", "monthlyy", ""):
            self.assertFalse(self.add("Rejected", repeat=repeat)["ok"], repeat)
        self.assertTrue(self.add("Inclusive", repeat="weekly", until="2026-10-21")["ok"])
        for until in ("not a date", "2026-10-06", "2026-02-30"):
            self.assertFalse(self.add("Invalid", repeat="daily", until=until)["ok"], until)
        self.assertFalse(self.add("No repeat", until="2026-11-01")["ok"])
        old = {"id": "prior-version", "title": "Old", "date": "2026-10-07",
               "time": "", "calendar": "Home"}
        self.store.write_text(json.dumps([old]))
        self.assertTrue(self.helper("list")["ok"])
        self.assertEqual(self.helper("list")["events"][0], old)

    def test_recurrence_edits_reject_stale_snapshot(self):
        old = self.add("Every week", repeat="weekly", until="2026-10-31")["event"]
        update = {**old, "expected": old, "repeat": "monthly", "until": "2027-01-01"}
        self.assertTrue(self.helper("edit", old["id"], event=update)["ok"])
        stale = {**old, "expected": old, "title": "Stale edit"}
        r = self.helper("edit", old["id"], event=stale)
        self.assertTrue(r.get("conflict"), r)
        self.assertEqual(self.helper("list")["events"][0]["repeat"], "monthly")
        copy = self.helper("duplicate", old["id"])["event"]
        self.assertEqual((copy["repeat"], copy["until"]), ("monthly", "2027-01-01"))
        self.assertNotEqual(copy["id"], old["id"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
