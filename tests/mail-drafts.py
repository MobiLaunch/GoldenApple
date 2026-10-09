#!/usr/bin/env python3
"""Mail drafts survive reopen, stay private and refuse damaged-file replacement."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HELPER = Path(__file__).resolve().parents[1] / "apps/mail/helper.py"


class Drafts(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.state = Path(self.tmp.name)
        self.env = dict(os.environ, XDG_STATE_HOME=str(self.state))
        self.path = self.state / "golden-gate/mail-draft.json"

    def tearDown(self):
        self.tmp.cleanup()

    def call(self, cmd, data=None):
        p = subprocess.run([sys.executable, str(HELPER), cmd], input=json.dumps(data),
                           text=True, capture_output=True, env=self.env, timeout=10)
        return json.loads(p.stdout), p.returncode

    def test_roundtrip_and_private_permissions(self):
        self.assertEqual(self.call("draft-load")[0]["draft"], dict(to="", subject="", body=""))
        draft = dict(to="sam@example.com", subject="Draft — one", body="Line one\nLine two 📝")
        self.assertTrue(self.call("draft-save", draft)[0]["ok"])
        self.assertEqual(self.call("draft-load")[0]["draft"], draft)
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)
        self.assertTrue(self.call("draft-save", dict(to="", subject="", body=""))[0]["ok"])
        self.assertEqual(self.call("draft-load")[0]["draft"]["body"], "")

    def test_damaged_draft_is_never_replaced(self):
        self.path.parent.mkdir(parents=True)
        self.path.write_text('{"body":')
        self.assertFalse(self.call("draft-load")[0]["ok"])
        self.assertFalse(self.call("draft-save", dict(body="new"))[0]["ok"])
        self.assertEqual(self.path.read_text(), '{"body":')

    def test_wrong_types_are_refused(self):
        for data in ([], dict(body=["bad"]), dict(to=42)):
            r, code = self.call("draft-save", data)
            self.assertFalse(r["ok"])
            self.assertEqual(code, 1)
            self.assertFalse(self.path.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
