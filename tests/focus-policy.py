#!/usr/bin/env python3
"""Run the shared production Focus policy in Qt's JavaScript engine."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

os.environ["TZ"] = "America/Chicago"
time.tzset()
from PySide6.QtCore import QCoreApplication
from PySide6.QtQml import QJSEngine

ROOT = Path(__file__).resolve().parents[1]
APP = QCoreApplication([])


class Policy(unittest.TestCase):
    def setUp(self):
        self.js = QJSEngine()
        loaded = self.js.evaluate((ROOT / "apps/lib/FocusPolicy.js").read_text().replace(".pragma library", ""))
        self.assertFalse(loaded.isError(), loaded.toString())

    def call(self, name, *args):
        result = self.js.evaluate(name + "(" + ",".join(json.dumps(a) for a in args) + ")")
        self.assertFalse(result.isError(), result.toString())
        return result.toVariant()

    def date(self, value):
        return self.js.evaluate("new Date(" + json.dumps(value) + ").getTime()").toNumber()

    def test_temporary_focus_expires_at_saved_deadline(self):
        now = self.date("2026-10-08T22:00:00-05:00")
        session = self.call("start", 60, now)
        self.assertEqual(session["until"], now + 3600000)
        self.assertTrue(self.call("state", {"session":session}, now + 3599999)["active"])
        self.assertFalse(self.call("state", {"session":session}, now + 3600000)["active"])

    def test_permanent_and_legacy_preferences(self):
        self.assertTrue(self.call("state", {"dnd":True}, 123)["active"])
        self.assertTrue(self.call("state", {"session":self.call("start",0,123)}, 10**13)["active"])
        self.assertFalse(self.call("state", {"dnd":True,"session":{"on":False}}, 123)["active"])

    def test_restart_uses_persisted_epoch_not_a_new_countdown(self):
        with tempfile.TemporaryDirectory() as directory:
            env = {**os.environ,"XDG_CONFIG_HOME":directory}
            start = self.date("2026-10-08T10:00:00-05:00")
            session = self.call("start",60,start)
            subprocess.run([sys.executable,str(ROOT/"apps/setup/pref-helper.py"),"focus.session",json.dumps(session)],env=env,check=True)
            saved=json.loads((Path(directory)/"golden-gate/desktop.json").read_text())
            self.assertEqual(saved["focus"]["session"],session)
            self.assertFalse(self.call("state",saved["focus"],start+3600000)["active"])

    def test_weekday_overnight_schedule_belongs_to_start_day(self):
        p={"schedule":{"enabled":True,"days":[5],"start":1320,"end":420}}
        self.assertFalse(self.call("state",p,self.date("2026-10-09T21:59:59-05:00"))["active"])
        self.assertTrue(self.call("state",p,self.date("2026-10-09T22:00:00-05:00"))["active"])
        self.assertTrue(self.call("state",p,self.date("2026-10-10T06:59:59-05:00"))["active"])
        self.assertFalse(self.call("state",p,self.date("2026-10-10T07:00:00-05:00"))["active"])
        self.assertFalse(self.call("state",p,self.date("2026-10-10T22:00:00-05:00"))["active"])

    def test_daytime_schedule_and_disabled_or_invalid_schedules(self):
        now=self.date("2026-10-08T10:00:00-05:00")
        schedule={"enabled":True,"days":[4],"start":540,"end":1020}
        self.assertTrue(self.call("state",{"schedule":schedule},now)["active"])
        for changes in ({"enabled":False},{"days":[]},{"end":540},{"start":-1},{"end":1440},{"start":"09:00"}):
            self.assertFalse(self.call("state",{"schedule":{**schedule,**changes}},now)["active"])

    def test_turn_off_pauses_only_this_scheduled_period(self):
        now=self.date("2026-10-08T10:00:00-05:00")
        p={"schedule":{"enabled":True,"days":[4,5],"start":540,"end":1020}}
        p["session"]=self.call("stop",p,now)
        self.assertEqual(self.call("state",p,now)["source"],"paused")
        self.assertFalse(self.call("state",p,self.date("2026-10-08T16:59:59-05:00"))["active"])
        self.assertTrue(self.call("state",p,self.date("2026-10-09T09:00:00-05:00"))["active"])

    def test_manual_duration_can_extend_schedule_and_then_resume_it(self):
        now=self.date("2026-10-08T16:30:00-05:00")
        p={"schedule":{"enabled":True,"days":[4],"start":540,"end":1020},"session":self.call("start",120,now)}
        self.assertEqual(self.call("state",p,now)["until"],now+7200000)
        self.assertTrue(self.call("state",p,now+3600000)["active"])
        self.assertFalse(self.call("state",p,now+7200000)["active"])

    def test_schedule_uses_local_calendar_across_daylight_saving(self):
        p={"schedule":{"enabled":True,"days":[6],"start":1320,"end":420}}
        now=self.date("2026-10-31T22:00:00-05:00")
        result=self.call("state",p,now)
        self.assertEqual(result["until"],self.date("2026-11-01T07:00:00-06:00"))
        self.assertEqual(result["until"]-now,10*3600000)

    def test_app_exceptions_canonical_names_and_critical_opt_in(self):
        key=self.call("appKey","org.goldengate.Clock")
        self.assertNotIn(".",key)
        p={"allowedApps":{key:True}}
        self.assertTrue(self.call("allows",p,"Clock",1))
        self.assertTrue(self.call("allows",p,"org.goldengate.Clock",1))
        self.assertFalse(self.call("allows",p,"Mail",2))
        self.assertTrue(self.call("allows",{"allowCritical":True},"Mail",2))
        self.assertFalse(self.call("allows",{"allowCritical":True},"Mail",1))
    def test_legacy_app_preferences_are_retained_and_canonical_choice_wins(self):
        self.assertEqual(self.call("appChoice",{"clock":{"allow":False}},"org.goldengate.Clock"),{"allow":False})
        choices={"clock":{"allow":False},"org.goldengate.clock":{"allow":True}}
        self.assertEqual(self.call("appChoice",choices,"Clock"),{"allow":True})
        self.assertEqual(self.call("appChoice",{"chat":{"allow":False}},"org.other.Chat"),{})


if __name__ == "__main__": unittest.main(verbosity=2)
