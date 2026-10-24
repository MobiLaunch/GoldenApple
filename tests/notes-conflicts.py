#!/usr/bin/env python3
"""Notes never writes over what someone else wrote (apps/notes/NoteEditor.qml,
against real files through the preview harness): a note changed in another
app since it was opened, or a new note whose name was taken meanwhile, is
left alone and this version is saved as a note of its own, with a notice;
renaming a note to follow its title never replaces another note. Ordinary
saves still go to the note's own file."""
import json
import os
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
from pathlib import Path
import sys
import tempfile
import unittest

from PySide6.QtCore import QMetaObject, QObject, QUrl, Q_ARG
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlExpression
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/preview"))
import preview
APP = QGuiApplication([])


class Writing(preview.Preview):
    def __init__(self, env):
        super().__init__(env, str(ROOT / "apps"), "'default'")
        self._allow_writes = True

    # notes/trash.py runs for real (the stub Process otherwise answers nothing).
    @preview.Slot("QVariant", result="QVariantMap")
    def run(self, cmd):
        cmd = cmd.toVariant() if hasattr(cmd, "toVariant") else cmd
        if any(str(c).endswith("notes/trash.py") for c in cmd):
            import subprocess
            p = subprocess.run([str(c) for c in cmd], capture_output=True, text=True)
            return {"stdout": p.stdout, "stderr": p.stderr, "code": p.returncode}
        return {"stdout": "", "stderr": "", "code": 0}


class Conflicts(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name) / "Notes"
        (self.root / "Notes").mkdir(parents=True)
        self.fake = Writing({"HOME": self.tmp.name})
        self.view = QQuickView()
        self.view.engine().addImportPath(str(ROOT / "tools/preview/qml"))
        self.view.engine().rootContext().setContextProperty("__preview", self.fake)
        c = QQmlComponent(self.view.engine())
        c.setData(b'import QtQuick\nimport "../apps/notes"\nNoteEditor { objectName: "ed"; width: 600; height: 400 }',
                  QUrl.fromLocalFile(str(ROOT / "tests" / "NotesFixture.qml")))
        self.assertEqual(c.status(), QQmlComponent.Ready, "\n".join(e.toString() for e in c.errors()))
        self.c = c
        self.ed = c.create()
        self.ed.setProperty("root", str(self.root))

    def tearDown(self):
        self.tmp.cleanup()

    def js(self, expr):
        v = QQmlExpression(self.view.engine().rootContext(), self.ed, expr).evaluate()[0]
        return v.toVariant() if hasattr(v, "toVariant") else v

    def open(self, path):
        self.ed.setProperty("path", str(path))
        QTest.qWait(150)

    def type(self, text):
        stack = [self.ed]
        while stack:
            it = stack.pop()
            if it.objectName() == "notesEditText":
                it.setProperty("text", text)
                break
            stack.extend(it.childItems())
        QMetaObject.invokeMethod(self.ed, "changed")

    def save(self):
        ok = self.js("save()")
        QTest.qWait(500)
        return ok

    def test_ordinary_save_and_rename_by_title(self):
        p = self.root / "Notes/Groceries.md"
        p.write_text("Groceries\n\nmilk\n")
        self.open(p)
        self.type("Shopping\n\nmilk, eggs")
        self.assertTrue(self.save())
        self.assertFalse(p.exists(), "renamed to follow the title")
        self.assertIn("eggs", (self.root / "Notes/Shopping.md").read_text())
        self.assertEqual(self.ed.property("loadedPath"), str(self.root / "Notes/Shopping.md"))

    def test_changed_elsewhere_is_kept(self):
        p = self.root / "Notes/Plan.md"
        p.write_text("Plan\n\nmine\n")
        self.open(p)
        p.write_text("Plan\nedited in another app")            # someone else saves meanwhile
        self.type("Plan\n\nmy edit")
        self.assertTrue(self.save())
        self.assertEqual(p.read_text(), "Plan\nedited in another app", "theirs left alone")
        copies = [f for f in (self.root / "Notes").glob("Plan *.md")]
        self.assertEqual(len(copies), 1)
        self.assertIn("my edit", copies[0].read_text(), "ours saved as its own note")
        self.assertIn("changed somewhere else", self.ed.property("notice"))

    def test_rename_never_replaces_another_note(self):
        (self.root / "Notes/Ideas.md").write_text("Ideas\ntheirs")    # created after the list was read
        p = self.root / "Notes/New Note.md"
        p.write_text("")
        self.open(p)
        self.type("Ideas\n\nmine")
        self.assertTrue(self.save())
        self.assertEqual((self.root / "Notes/Ideas.md").read_text(), "Ideas\ntheirs")
        self.assertIn("mine", (self.root / "Notes/Ideas 2.md").read_text())

    def test_new_note_name_taken_meanwhile(self):
        p = self.root / "Notes/New Note.md"
        self.open(p)                                              # a new note: no file yet
        self.ed.setProperty("fresh", True)
        p.write_text("Someone else's note")                       # the name is taken now
        self.type("Mine")
        self.assertTrue(self.save())
        self.assertEqual(p.read_text(), "Someone else's note")
        self.assertTrue(any("Mine" in f.read_text() for f in (self.root / "Notes").glob("*.md") if f != p))


if __name__ == "__main__":
    unittest.main(verbosity=2)
