#!/usr/bin/env python3
"""Mail after sign-in: real IMAP response parsing and responsive UI contracts."""
from __future__ import annotations
import contextlib
from email.message import EmailMessage
import importlib.util
import io
import json
from pathlib import Path
from unittest.mock import patch
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("mail_helper_test", ROOT / "apps/mail/helper.py")
mail = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mail)


class FakeIMAP:
    def __init__(self, reject_batch=False, count=3):
        self.reject_batch = reject_batch
        self.count = count
        self.calls = []
        self.closed = False

    def select(self, name, readonly=False):
        assert name == "INBOX" and readonly
        return "OK", [b"3"]

    def uid(self, command, *args):
        self.calls.append((command, *args))
        if command == "search":
            return "OK", [b" ".join(str(n).encode() for n in range(1, self.count + 1))]
        assert command == "fetch"
        sequence = args[0]
        if self.reject_batch and "," in sequence:
            return "BAD", [b"unsupported UID set"]
        numbers = sequence.split(",")
        parts = []
        for number in reversed(numbers):
            msg = EmailMessage()
            msg["From"] = "Test User " + number + " <person@example.org>"
            msg["Date"] = "Fri, 09 Oct 2026 10:05:00 -0500"
            msg["Subject"] = "Subject " + number
            flags = r"\Seen" if number == "2" else ""
            meta = f"7 (UID {number} FLAGS ({flags}) BODY[HEADER.FIELDS (SUBJECT FROM DATE)] {{123}}".encode()
            parts.append((meta, msg.as_bytes()))
            parts.append(b")")
        return "OK", parts

    def logout(self):
        self.closed = True


class MailLayoutTests(unittest.TestCase):
    def collect_inbox(self, reject_batch):
        server = FakeIMAP(reject_batch)
        stream = io.StringIO()
        with patch.object(mail, "configured", return_value=({"email": "me@example.org"}, "secret")), \
             patch.object(mail, "imap_client", return_value=server), \
             contextlib.redirect_stdout(stream):
            status = mail.cmd_list()
        self.assertEqual(status, 0)
        output = json.loads(stream.getvalue())
        self.assertTrue(output["ok"])
        return server, output["messages"]

    def test_imap_headers_batch_one_request_for_three_messages(self):
        server, rows = self.collect_inbox(False)
        self.assertEqual(len([c for c in server.calls if c[0] == "fetch"]), 1)
        self.assertEqual([r["uid"] for r in rows], ["3", "2", "1"])
        self.assertEqual([r["subject"] for r in rows], ["Subject 3", "Subject 2", "Subject 1"])
        self.assertEqual([r["unread"] for r in rows], [True, False, True])
        self.assertTrue(server.closed)

    def test_imap_falls_back_to_individual_fetch_for_older_servers(self):
        server, rows = self.collect_inbox(True)
        self.assertEqual(len([c for c in server.calls if c[0] == "fetch"]), 4)
        self.assertEqual([r["uid"] for r in rows], ["3", "2", "1"])
        self.assertFalse(rows[1]["unread"])

    def test_eighty_messages_need_only_four_batch_fetches(self):
        server = FakeIMAP(count=80)
        stream = io.StringIO()
        with patch.object(mail, "configured", return_value=({"email": "me@example.org"}, "secret")), \
             patch.object(mail, "imap_client", return_value=server), \
             contextlib.redirect_stdout(stream):
            self.assertEqual(mail.cmd_list(), 0)
        payload = json.loads(stream.getvalue())
        self.assertTrue(payload["ok"])
        self.assertEqual(len(payload["messages"]), 80)
        self.assertEqual(payload["messages"][0]["uid"], "80")
        self.assertEqual(len([c for c in server.calls if c[0] == "fetch"]), 4)

    def test_parser_never_misattributes_other_uids(self):
        server = FakeIMAP()
        _, parts = server.uid("fetch", "1,2,3", "(UID FLAGS BODY.PEEK[HEADER.FIELDS (SUBJECT FROM DATE)])")
        rows = mail.parse_header_items(parts, {"2"})
        self.assertEqual(list(rows), ["2"])
        self.assertEqual(rows["2"]["subject"], "Subject 2")

    def test_logged_in_content_begins_below_the_toolbar(self):
        qml = (ROOT / "apps/mail.qml").read_text()
        self.assertIn("fullSizeContent: false", qml)
        self.assertNotIn("fullSizeContent: true", qml)
        for part in ("mailWorkspace", "mailMessageListPane", "mailReadingPane",
                     "mailComposerPane", "mailDraftsPane", "mailSplitDivider"):
            self.assertIn('objectName: "' + part + '"', qml)
        self.assertIn("readonly property bool compactReading: width < 700", qml)
        self.assertIn("mail.width - messageListPane.width - mailDivider.width", qml)
        self.assertIn("anchors { fill: parent; leftMargin: 28;", qml)
        self.assertIn("top: composeFields.bottom; bottom: composeActions.top", qml)
        self.assertNotIn("parent.height - 118", qml)
        self.assertIn('objectName: "mailSetupScroller"', qml)
        self.assertIn('function leaveMessage()', qml)
        self.assertIn('text: "Try Again"', qml)
        self.assertIn("win.toolbarLeadingEnd", qml)

    def test_search_unread_reply_and_saved_drafts_have_handlers(self):
        qml = (ROOT / "apps/mail.qml").read_text()
        for name in ("function senderName(", "function address(", "function reply()",
                     "function forward()", "function read(", "property bool unreadOnly: false",
                     "readonly property var filteredMessages", "property bool draftReady: false"):
            self.assertIn(name, qml)
        self.assertIn("queuedUid = uid", qml)
        self.assertIn("if (item.uid === mail.selectedUid)", qml)
        self.assertIn("selectedFolder = \"inbox\"", qml)
        self.assertNotIn("if (mail.composeTo || mail.composeSubject || mail.composeBody) mail.composing = true", qml)
        self.assertIn("onTextChanged: mail.composeBody = text", qml)

    def test_split_panes_respect_minimum_content_width(self):
        # Golden Gate's minimum Mail window is 760 px; at that size a
        # sidebar can take 205 px. The content must never have negative
        # dimensions or two cramped unreadable side-by-side panes.
        for window_width in (760, 800, 900, 950, 1120, 1440):
            for sidebar in (0, 205):
                body = window_width - sidebar
                compact = body < 700
                if compact:
                    self.assertGreaterEqual(body, 500)
                else:
                    list_width = max(304, min(336, body - 350))
                    reader_width = body - list_width - 7
                    self.assertGreaterEqual(list_width, 304)
                    self.assertGreaterEqual(reader_width, 350)

    def test_visual_previews_cover_signed_in_mail(self):
        suite = (ROOT / "tests/qml-load.py").read_text()
        preview = (ROOT / "tools/preview/preview.py").read_text()
        for item in ("mail-inbox-wide", "mail-reader-wide", "mail-reader-compact",
                     "mail-compose", "mail-drafts"):
            self.assertIn(item, suite)
        self.assertIn("mail.setProperty(\"configured\", True)", preview)
        self.assertIn("mailMessageReader", suite)


if __name__ == "__main__":
    unittest.main(verbosity=2)
