#!/usr/bin/env python3
"""CalDAV read-only parser and secret-free local tests."""
import importlib.util
from pathlib import Path
from contextlib import nullcontext
import sys
import tempfile
import unittest
from unittest.mock import patch, MagicMock
import urllib.request
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "apps/calendar"))
spec = importlib.util.spec_from_file_location("calendar_caldav", ROOT / "apps/calendar/caldav.py")
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)

def fixture(*rows):
    return "BEGIN:VCALENDAR\r\n" + "\r\n".join(rows) + "\r\nEND:VCALENDAR\r\n"

def vevent(uid, when, summary="Meeting", extra=""):
    return "\r\n".join(["BEGIN:VEVENT", f"UID:{uid}", f"DTSTART:{when}",
                         f"SUMMARY:{summary}", extra, "END:VEVENT"])

class CalDav(unittest.TestCase):
    def test_private_https_url_only(self):
        self.assertEqual(sync.validate_url("https://calendar.example.test/users/me/"), "https://calendar.example.test/users/me/")
        self.assertEqual(sync.validate_url("https://example.test:5006/calendar/"), "https://example.test:5006/calendar/")
        for url in ("http://calendar.example.test/", "file:///etc/passwd",
                    "https://username:password@example.test/",
                    "https://example.test/#fragment", "https://example.test:0/"):
            with self.assertRaises(ValueError, msg=url):
                sync.validate_url(url)

    def test_parse_one_time_and_simple_repeat(self):
        text = fixture(
            vevent("a-1", "20261009T143000Z", r"Project\, review"),
            vevent("a-2", "20261010", "All day"),
            vevent("a-3", "20261011T090000", "Weekly", "RRULE:FREQ=WEEKLY;INTERVAL=1;UNTIL=20261201"))
        events, ignored = sync.parse_ics(text)
        self.assertEqual(ignored, 0)
        self.assertEqual(len(events), 3)
        self.assertTrue(all(e["remote"] and e["reminder"] == -1 for e in events))
        self.assertEqual(events[0]["title"], "Project, review")
        self.assertEqual(events[1]["time"], "")
        self.assertEqual(events[2]["repeat"], "weekly")
        self.assertEqual(events[2]["until"], "2026-12-01")

    def test_recurrence_exceptions_not_falsely_displayed(self):
        data = fixture(vevent("same", "20261008T090000", "Original", "RRULE:FREQ=WEEKLY"),
                       vevent("same", "20261009T090000", "Changed", "RECURRENCE-ID:20261015T090000"),
                       vevent("complex", "20261009", "Unsupported", "RRULE:FREQ=WEEKLY;BYDAY=MO,WE"))
        rows, ignored = sync.parse_ics(data)
        self.assertEqual(rows, [])
        self.assertEqual(ignored, 3)

    def test_oversized_response_rejected(self):
        with self.assertRaises(ValueError):
            sync.parse_ics("a" * (sync.MAX_BYTES + 1))

    def test_store_is_private_and_bad_cache_is_not_replaced(self):
        with tempfile.TemporaryDirectory() as tmp:
            f = Path(tmp) / "caldav-events.json"
            sync.private_json(f, [{"id":"remote"}])
            self.assertEqual(f.stat().st_mode & 0o777, 0o600)
            self.assertEqual(f.read_text().count("remote"), 1)
            f.write_text("not json")
            self.assertEqual(f.read_text(), "not json")

    def test_redirects_never_forward_credentials(self):
        handler = sync.NoRedirect()
        request = urllib.request.Request("https://calendar.example.test/private",
                                         headers={"Authorization":"Basic confidential"})
        with self.assertRaises(ValueError):
            handler.redirect_request(request, None, 302, "Moved", {}, "https://other.example.test/")

    def test_auto_refresh_unit_install_and_stop(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            cfg = home / "account.json"
            sync.private_json(cfg, {"username": "sample", "url":"https://calendar.example.test/home/"})
            with patch.object(sync, "CONFIG", cfg), patch.object(sync, "USER_UNITS", home/"units"), patch.object(sync, "systemctl") as run:
                sync.set_auto(True)
                self.assertTrue((home/"units/gg-calendar-caldav.timer").exists())
                self.assertIn("15min", (home/"units/gg-calendar-caldav.timer").read_text())
                self.assertIn(" sync", (home/"units/gg-calendar-caldav.service").read_text())
                self.assertTrue(sync.auto_running())
                sync.set_auto(True)
                sync.set_auto(False)
                self.assertFalse((home/"units/gg-calendar-caldav.timer").exists())
                self.assertFalse(sync.auto_running())
                run.assert_any_call("disable","--now","gg-calendar-caldav.timer")

    def test_changed_account_cannot_be_overwritten_by_old_sync(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            cfg = root/"account.json"
            cache = root/"events.json"
            sync.private_json(cfg, {"username":"A","url":"https://calendar.example.test/A"})
            def stale_remote(*args):
                # Imagine Disconnect or switching accounts while the REPORT is in flight.
                cfg.unlink()
                return ([{"id":"caldav-remote", "title":"Old data"}], 0)
            with patch.object(sync, "CONFIG", cfg), patch.object(sync, "CACHE", cache), patch.object(sync, "secret_tool", return_value="password"), patch.object(sync, "fetch_events", side_effect=stale_remote), patch.object(sync.local, "locked", side_effect=nullcontext):
                self.assertEqual(sync.command("sync"), 1)
            self.assertFalse(cache.exists(), "an in-flight request cannot restore a disconnected calendar")

    def test_disconnect_stops_timer_and_preserves_local_store(self):
        with tempfile.TemporaryDirectory() as tmp:
            cfg = Path(tmp)/"account.json"
            cache = Path(tmp)/"cache.json"
            sync.private_json(cfg, {"username":"A","url":"https://calendar.example.test/A"})
            sync.private_json(cache, [{"id":"remote"}])
            with patch.object(sync,"CONFIG",cfg), patch.object(sync,"CACHE",cache), patch.object(sync,"set_auto") as timer, patch.object(sync,"secret_tool",return_value=""), patch.object(sync.local,"locked",side_effect=nullcontext):
                self.assertEqual(sync.command("disconnect"),0)
            timer.assert_called_once_with(False)
            self.assertFalse(cache.exists())
            self.assertFalse(cfg.exists())

if __name__ == "__main__":
    unittest.main(verbosity=2)
