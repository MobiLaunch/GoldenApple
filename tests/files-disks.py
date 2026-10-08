#!/usr/bin/env python3
"""Files shows what's on the disks: Locations lists the system's volume and
every other volume you can open (not boot or EFI partitions), with an eject
button on external ones; Computer (⇧⌘C) shows each with its free space; the
path bar runs from the disk down to the folder, with the room left; and
⇧⌘. shows hidden files. Disks come from tools/preview/fixtures/disks.json."""
import os
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
from pathlib import Path
import sys
import tempfile
import unittest

from PySide6.QtCore import QMetaObject, QObject, QUrl, Q_ARG
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/preview"))
import preview
APP = QGuiApplication([])


class FilesDisks(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp())
        for d in ("Documents", "Downloads"):
            (self.home / d).mkdir()
        (self.home / ".config").mkdir()
        (self.home / "notes.txt").write_text("hi")
        env = {"HOME": str(self.home), "USER": "you", "XDG_CONFIG_HOME": str(self.home / ".config"),
               "XDG_DATA_HOME": str(self.home / ".local/share"), "XDG_RUNTIME_DIR": str(self.home),
               "GG_DISKS_FIXTURE": str(ROOT / "tools/preview/fixtures/disks.json")}
        self.view = QQuickView()
        self.fake = preview.Preview(env, str(ROOT / "apps"), "'default'")
        self.view.engine().addImportPath(str(ROOT / "tools/preview/qml"))
        self.view.engine().rootContext().setContextProperty("__preview", self.fake)
        component = QQmlComponent(self.view.engine())
        component.setData(b'import QtQuick\nItem { width: 1100; height: 700; Loader { source: "../apps/files.qml" } }',
                          QUrl.fromLocalFile(str(ROOT / "tests" / "FilesFixture.qml")))
        self.assertEqual(component.status(), QQmlComponent.Ready, "\n".join(e.toString() for e in component.errors()))
        self.root = component.create()
        self.component = component
        self.files = None
        for _ in range(80):
            QTest.qWait(50)
            bar = self.root.findChild(QObject, "filesPathBar")
            if bar is not None and self.value_of(bar.parent(), "disks"):
                self.files = bar.parent()
                break
        self.assertIsNotNone(self.files, "Files loaded, with its disks")

    def tearDown(self):
        self.root.deleteLater()
        APP.processEvents()

    @staticmethod
    def value_of(obj, name):
        v = obj.property(name)
        return v.toVariant() if hasattr(v, "toVariant") else v

    def value(self, name):
        return self.value_of(self.files, name)

    def call(self, name, *args):
        QMetaObject.invokeMethod(self.files, name, *[Q_ARG("QVariant", a) for a in args])

    def wait_for(self, check, ms=4000):
        for _ in range(ms // 50):
            if check():
                return True
            QTest.qWait(50)
        return check()

    def test_locations(self):
        names = [v["name"] for v in self.value("volumes")]
        self.assertEqual(names, ["CitronOS", "Windows", "BACKUP"], "not the EFI partition")
        vols = {v["name"]: v for v in self.value("volumes")}
        self.assertFalse(vols["Windows"]["mounted"])
        self.assertTrue(vols["BACKUP"]["removable"] and vols["BACKUP"]["mounted"])
        shown = set()
        top = self.files
        while top.parentItem() is not None:
            top = top.parentItem()
        stack = [top]
        while stack:
            item = stack.pop()
            stack.extend(item.childItems())
            if item.objectName().startswith("filesVolume:") and item.isVisible():
                shown.add(item.objectName().split(":", 1)[1])
        self.assertEqual(shown, set(names), "each in the sidebar")

    def test_path_bar(self):
        self.assertTrue(self.wait_for(lambda: self.value("free") > 0))
        crumbs = self.value("crumbs")
        self.assertEqual(crumbs[0]["name"], "CitronOS", "it starts at the disk")
        self.assertEqual(crumbs[0]["path"], "/")
        self.assertEqual(crumbs[-1]["path"], str(self.home))
        self.assertEqual(crumbs[-1]["kind"], "house")
        status = self.root.findChild(QObject, "filesStatus").property("text")
        self.assertRegex(status, r"^3 items, [\d.]+ [KMGT]?B available$")

    def test_computer(self):
        self.call("navigate", "computer:", True)
        self.assertTrue(self.wait_for(lambda: "BACKUP" in [e["name"] for e in self.value("entries")]))
        entries = {e["name"]: e for e in self.value("entries")}
        self.assertEqual(len(entries), 3)
        self.assertEqual(entries["BACKUP"]["detail"], "1.2 TB free of 2 TB")
        self.assertEqual(entries["CitronOS"]["detail"], "320 GB free of 500 GB")
        self.assertEqual(entries["Windows"]["detail"], "Not mounted")
        self.assertEqual(self.value("title"), "Computer")
        self.assertFalse(self.root.findChild(QObject, "filesPathBar").property("visible"))

    def test_a_deep_folder_folds_its_ancestors(self):
        deep = self.home
        for name in ("Projects", "Client Work 2026", "Golden Gate Redesign", "Assets and Exports", "Final Deliverables", "Print"):
            deep = deep / name
        deep.mkdir(parents=True)
        self.call("navigate", str(deep), True)
        self.assertTrue(self.wait_for(lambda: self.value("crumbs") and self.value("crumbs")[-1]["path"] == str(deep)))
        QTest.qWait(150)
        row = self.root.findChild(QObject, "filesCrumbs")
        folded = next((i for i in self.walk(row) if i.objectName() == "filesCrumbsFolded"), None)
        self.assertIsNotNone(folded, "the middle folders fold into …")
        self.assertTrue(folded.isVisible())
        self.assertEqual(row.property("x"), 0, "nothing is cropped: the disk and this folder both show whole")
        names = [t.property("text") for t in self.walk(row) if t.metaObject().className().startswith("QQuickText")]
        self.assertEqual(names[0], "CitronOS")
        self.assertEqual(names[-1], "Print")
        self.assertIn("…", names)

    def test_a_very_long_name_is_shortened_not_cropped(self):
        deep = self.home / ("Quarterly Report Drafts and Reviews for the Board Meeting " * 3).strip() / ("An Extremely Long Folder Name " * 6).strip()
        deep.mkdir(parents=True)
        self.call("navigate", str(deep), True)
        self.assertTrue(self.wait_for(lambda: self.value("crumbs") and self.value("crumbs")[-1]["path"] == str(deep)))
        QTest.qWait(150)
        row = self.root.findChild(QObject, "filesCrumbs")
        box = row.parentItem()
        self.assertEqual(row.property("x"), 0, "the disk still shows: nothing pushed off the start")
        self.assertLessEqual(row.property("implicitWidth"), box.property("width") + 1, "the whole path fits the bar")
        texts = [t for t in self.walk(row) if t.metaObject().className().startswith("QQuickText")]
        self.assertEqual(texts[0].property("text"), "CitronOS")
        last = texts[-1]
        self.assertEqual(last.property("text"), deep.name, "the full name, shown shortened")
        self.assertTrue(last.property("truncated"), "shortened in the middle, not cropped")

    @staticmethod
    def walk(item):
        out, stack = [], [item]
        while stack:
            it = stack.pop(0)
            out.append(it)
            stack[0:0] = it.childItems()
        return out

    def test_hidden_files(self):
        self.assertTrue(self.wait_for(lambda: len(self.value("entries")) == 3))
        self.assertNotIn(".config", [e["name"] for e in self.value("entries")])
        self.call("toggleHidden")
        self.assertTrue(self.wait_for(lambda: ".config" in [e["name"] for e in self.value("entries")]), "shown with ⇧⌘.")
        self.call("toggleHidden")
        self.assertTrue(self.wait_for(lambda: ".config" not in [e["name"] for e in self.value("entries")]))

    def test_opening_an_unmounted_volume_mounts_it(self):
        windows = next(v for v in self.value("volumes") if v["name"] == "Windows")
        self.call("openVolume", windows)
        # The disks are a sample: the mount is asked for, refused (nothing is sent
        # for a device that may not exist), and why is said in the path bar.
        self.assertTrue(self.wait_for(lambda: self.value("notice") != ""), "a mount was attempted")
        self.assertIn("sample disks", self.value("notice"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
