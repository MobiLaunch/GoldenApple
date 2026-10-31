#!/usr/bin/env python3
"""Mac-style Mail categories, Important state, VIP and live Dock badges.

All backends are faked; no real account, password, network, or desktop config
is read. Checks local IMAP flags against actual UID STORE semantics.
"""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "apps/mail/helper.py"


class FakeImap:
    def __init__(self):
        self.actions = []
    def select(self, folder, readonly=False):
        self.actions.append(("select", folder))
        return ("OK", [b""])
    def uid(self, command, uid, operation, flags):
        self.actions.append((command, uid, operation, flags))
        return ("OK", [b""])
    def logout(self):
        return "BYE"


class CategoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="gg-mail-categories-")
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.env = patch.dict(os.environ, {
            "XDG_CONFIG_HOME": str(root / "config"),
            "XDG_STATE_HOME": str(root / "state"),
        })
        self.env.start()
        self.addCleanup(self.env.stop)
        spec = importlib.util.spec_from_file_location("gg_mail_categories_test", HELPER)
        self.m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.m)
        self.cfg = {"email": "sample@example.net"}
        self.auth = patch.object(self.m, "configured", return_value=(self.cfg, "fake-secret"))
        self.auth.start()
        self.addCleanup(self.auth.stop)

    def test_classification_and_manual_override_are_local(self):
        classify = self.m.classify_mail
        self.assertEqual(classify("friend@site.test", "Dinner plans"), "primary")
        self.assertEqual(classify("orders@example.test", "Your receipt"), "transactions")
        self.assertEqual(classify("newsletter@example.test", "Weekly digest"), "updates")
        self.assertEqual(classify("offers@example.test", "Limited time discount"), "promotions")
        self.assertNotIn("password", str(self.m.MAIL_META))
        self.assertEqual(self.m.cmd_category("42", "promotions"), 0)
        self.assertEqual(self.m.load_mail_meta()["sample@example.net"]["labels"]["42"], "promotions")
        self.assertEqual(self.m.MAIL_META.stat().st_mode & 0o777, 0o600)
        messages = [{"uid": "42", "from": "Sam <sam@example.org>",
                     "subject": "Dinner plans", "unread": True},
                    {"uid": "43", "from": "Service <no-reply@company.test>",
                     "subject": "Your invoice", "unread": False}]
        self.m.annotate_messages(messages, "sample@example.net")
        self.assertEqual(messages[0]["category"], "promotions")
        self.assertEqual(messages[1]["category"], "transactions")
        self.assertFalse(messages[0]["vip"])

    def test_vip_is_exactly_the_sender_not_a_forged_display_name(self):
        self.assertEqual(self.m.cmd_vip("sam@example.org", True), 0)
        messages = [
            {"uid": "5", "from": "Sam <sam@example.org>", "subject": "Hi"},
            {"uid": "6", "from": "'sam@example.org' <bad@example.org>", "subject": "Hi"},
        ]
        self.m.annotate_messages(messages, "sample@example.net")
        self.assertTrue(messages[0]["vip"])
        self.assertFalse(messages[1]["vip"])
        self.assertEqual(self.m.cmd_vip("sam@example.org", False), 0)
        self.m.annotate_messages(messages, "sample@example.net")
        self.assertFalse(messages[0]["vip"])
        self.assertNotEqual(self.m.cmd_vip("not an email", True), 0)

    def test_real_imap_important_round_trip(self):
        fake = FakeImap()
        with patch.object(self.m, "imap_client", return_value=fake):
            self.assertEqual(self.m.cmd_flag("123", True), 0)
            self.assertEqual(self.m.cmd_flag("123", False), 0)
        self.assertEqual(fake.actions[1], ("store", "123", "+FLAGS", "(\\Flagged)"))
        self.assertEqual(fake.actions[3], ("store", "123", "-FLAGS", "(\\Flagged)"))
        self.assertNotEqual(self.m.cmd_flag("../123", True), 0)
        self.assertNotEqual(self.m.cmd_category("foo", "primary"), 0)
        self.assertNotEqual(self.m.cmd_category("123", "bad"), 0)

    def test_ui_and_notification_contracts(self):
        qml = (ROOT / "apps/mail.qml").read_text()
        center = (ROOT / "shell/Notifications.qml").read_text()
        dock = (ROOT / "shell/Dock.qml").read_text()
        sliders = (ROOT / "apps/lib/LevelSlider.qml").read_text()
        cc = (ROOT / "shell/ControlCenter.qml").read_text()
        for token in ('"primary"', '"transactions"', '"updates"', '"promotions"',
                      '"flagged"', '"vip"', '"unread"'):
            self.assertIn(token, qml)
        for name in ("flagProc", "categoryProc", "vipProc"):
            self.assertIn("id: " + name, qml)
        self.assertIn('menuParent: win.overlay', qml)
        self.assertIn("root.badgeEpoch++", center)
        self.assertIn("mail-badges.json", center)
        self.assertIn("Math.max(active, mailUnread)", center)
        self.assertIn("countFor(modelData.id", dock)
        self.assertIn('lens: 13', cc)
        self.assertIn('blurMax: 6', sliders)
        self.assertIn('import QtQuick.Effects', sliders)


if __name__ == "__main__":
    unittest.main(verbosity=2)
