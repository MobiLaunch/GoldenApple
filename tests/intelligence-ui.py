#!/usr/bin/env python3
"""Exercise real Qt selection/undo, stale draft protection and TextEdit saves.

Quickshell's test adapter supplies process replies; no network or keyring calls.
"""
import json
import os
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
from pathlib import Path
import sys
import tempfile
import unittest
from PySide6.QtCore import QCoreApplication, QEvent, QObject, Qt, QUrl, Slot
from PySide6.QtGui import QGuiApplication, QKeyEvent
from PySide6.QtQml import QQmlComponent
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest
from shiboken6 import delete

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/preview"))
import preview
APP = QGuiApplication([])


class Fixture(preview.Preview):
    reply = {"ok": True, "text": "A result", "images": [], "truncated": False}
    @Slot("QVariant", result="QVariantMap")
    def run(self, cmd):
        if hasattr(cmd, "toVariant"):
            cmd = cmd.toVariant()
        if any(str(v).endswith("helper.py") for v in cmd):
            return {"stdout": json.dumps(self.reply), "stderr": "", "code": 0}
        return super().run(cmd)


QML = '''import QtQuick
import "../apps/lib" as GG
Rectangle {
    width: 800; height: 640
    property string plain: editor.getText(0, editor.length)
    function seed(value, rich) { editor.textFormat = rich ? TextEdit.MarkdownText : TextEdit.PlainText; editor.text = value }
    function selectText(a, b) { editor.select(a, b) }
    function openTools() { editor.openWritingTools() }
    function undo() { editor.undo() }
    GG.TextArea { id: editor; objectName: "body"; anchors.fill: parent; writingContext: "document-one" }
}'''


class UI(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.view = QQuickView()
        self.fake = Fixture({"HOME": self.temp.name, "USER": "test"}, str(ROOT / "apps"), "'default'")
        self.view.engine().addImportPath(str(ROOT / "tools/preview/qml"))
        self.view.engine().rootContext().setContextProperty("__preview", self.fake)

    def load(self, text=QML, name="IntelligenceFixture.qml"):
        component = QQmlComponent(self.view.engine())
        url = QUrl.fromLocalFile(str(ROOT / "tests" / name))
        component.setData(text.encode(), url)
        self.assertEqual(component.status(), QQmlComponent.Ready, "\n".join(e.toString() for e in component.errors()))
        self.root = component.create()
        self.assertIsNotNone(self.root)
        self.view.setContent(url, component, self.root)
        self.component = component
        self.view.show(); self.view.requestActivate(); QTest.qWait(40)

    def tearDown(self):
        self.view.close(); delete(self.view); APP.processEvents()
        self.temp.cleanup()

    def result(self, value):
        self.root.openTools(); QTest.qWait(50)
        result = self.view.contentItem().findChild(QObject, "writingResult")
        self.assertIsNotNone(result)
        result.setProperty("text", value)
        return self.view.contentItem().findChild(QObject, "writingTools")

    def test_selected_text_replacement_and_single_undo(self):
        self.load(); self.root.seed("One bad sentence. Keep this.", False); self.root.selectText(0, 17)
        sheet = self.result("A better sentence.")
        sheet.apply()
        self.assertEqual(self.root.property("plain"), "A better sentence. Keep this.")
        self.root.undo()
        self.assertEqual(self.root.property("plain"), "One bad sentence. Keep this.")

    def test_markdown_editor_inserts_generated_html_literally(self):
        self.load(); self.root.seed("# A title\n\nA paragraph.", True)
        self.root.selectText(0, 7)
        sheet = self.result('<img src="https://example.invalid/pixel">')
        sheet.apply()
        self.assertIn('<img src="https://example.invalid/pixel">', self.root.property("plain"))
        self.root.undo(); self.assertIn("A title", self.root.property("plain"))

    def test_stale_document_is_never_replaced(self):
        self.load(); self.root.seed("Original", False)
        sheet = self.result("Replacement")
        self.root.seed("New unsaved changes", False)
        sheet.apply()
        self.assertEqual(self.root.property("plain"), "New unsaved changes")
        self.assertIn("document changed", sheet.property("message"))

    def test_switching_documents_even_with_same_text_prevents_replace(self):
        self.load(); self.root.seed("Original", False)
        sheet = self.result("Replacement")
        self.root.findChild(QObject, "body").setProperty("writingContext", "document-two")
        sheet.apply()
        self.assertEqual(self.root.property("plain"), "Original")

    def test_readonly_editors_do_not_open_tools(self):
        self.load(); self.root.seed("Original", False)
        self.root.findChild(QObject, "body").setProperty("readOnly", True)
        self.root.openTools(); QTest.qWait(30)
        self.assertIsNone(self.view.contentItem().findChild(QObject, "writingTools"))

    def load_textedit(self):
        self.load('''import QtQuick
Item { width: 1000; height: 780; Loader { source: "../apps/textedit.qml" } }''')
        QTest.qWait(60)
        doc = self.root.findChild(QObject, "textDocument")
        body = self.root.findChild(QObject, "textEditBody")
        self.assertIsNotNone(doc); self.assertIsNotNone(body)
        return doc, body

    def test_save_completion_does_not_mark_newer_edits_saved(self):
        doc, body = self.load_textedit()
        body.setProperty("text", "First version")
        doc.saveTo(str(Path(self.temp.name) / "note.txt"))
        body.setProperty("text", "Second version")
        QTest.qWait(80)
        self.assertEqual(doc.property("savedText"), "First version")
        self.assertTrue(doc.property("dirty"))
        self.assertEqual(body.property("text"), "Second version")

    def test_window_close_keeps_an_unsaved_draft_open(self):
        doc, body = self.load_textedit()
        body.setProperty("text", "Unsaved draft")
        self.root.findChild(QObject, "textEditWindow").closeWindow()
        self.assertTrue(self.root.findChild(QObject, "unsavedChanges").property("visible"))
        self.assertEqual(body.property("text"), "Unsaved draft")

    def test_failed_open_preserves_current_path_and_text(self):
        doc, body = self.load_textedit()
        doc.setProperty("path", "/original.txt")
        body.setProperty("text", "Important draft")
        self.fake.reply = {"ok": False, "error": "Permission denied"}
        doc.openPath("/unreadable.txt"); QTest.qWait(80)
        self.assertEqual(doc.property("path"), "/original.txt")
        self.assertEqual(body.property("text"), "Important draft")
        self.assertEqual(doc.property("error"), "Permission denied")
        self.assertFalse(doc.property("loading"))

    def test_ask_page_chats(self):
        # Ask Anything had no field to type into; it's a chat now: Return
        # sends, the exchange appears, the composer clears.
        self.load('''import QtQuick
Item { width: 1100; height: 820; Loader { source: "../apps/intelligence.qml" } }''')
        QTest.qWait(80)
        composer = self.root.findChild(QObject, "citronComposer")
        chat = self.root.findChild(QObject, "citronChat")
        self.assertIsNotNone(composer); self.assertIsNotNone(chat)
        self.fake.reply = {"ok": True, "text": "A citrus fruit.", "images": [], "truncated": False}

        def key(k, mods=Qt.NoModifier):
            # Straight to the field: the app's window isn't a real one here.
            for kind in (QEvent.KeyPress, QEvent.KeyRelease):
                QCoreApplication.sendEvent(composer, QKeyEvent(kind, k, mods, "\r"))

        composer.setProperty("text", "What is a lemon?")
        composer.setProperty("cursorPosition", 16)
        key(Qt.Key_Return, Qt.ShiftModifier); QTest.qWait(30)
        self.assertEqual(chat.property("count"), 0, "Shift+Return is a new line, not a send")
        self.assertEqual(composer.property("text"), "What is a lemon?\n")
        composer.setProperty("text", "What is a lemon?")
        key(Qt.Key_Return); QTest.qWait(150)
        self.assertEqual(chat.property("count"), 2)
        self.assertEqual(composer.property("text"), "")

if __name__ == "__main__":
    unittest.main()
