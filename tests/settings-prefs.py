#!/usr/bin/env python3
"""Settings' preference files: every one is replaced whole and atomically
(apps/settings/write-file.py), a failed write leaves the old file and is
reported in the window; gg-pref changes made at the same moment all stay;
and the keyboard variant Setup chose (such as ch(fr)) survives a change of
repeat rate."""
import os
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
import json
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from PySide6.QtCore import QMetaObject, QObject, QUrl, Q_ARG, Slot
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/preview"))
import preview
APP = QGuiApplication([])
WRITER = ROOT / "apps/settings/write-file.py"
PREF = ROOT / "apps/setup/pref-helper.py"


class Files(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, path, text):
        return subprocess.run([sys.executable, str(WRITER), str(path)], input=text, capture_output=True, text=True)

    def test_replaced_whole(self):
        f = self.dir / "gg/privacy.json"
        self.assertEqual(self.write(f, '{"location": false}\n').returncode, 0)
        self.assertEqual(json.loads(f.read_text()), {"location": False})
        self.assertEqual([p.name for p in f.parent.iterdir() if p.name.endswith(".tmp")], [], "no leftovers")

    def test_a_failed_write_keeps_the_old_file(self):
        f = self.dir / "privacy.json"
        f.write_text('{"location": true}\n')
        (self.dir / "blocked").write_text("a file, not a folder")
        p = self.write(self.dir / "blocked/privacy.json", "{}")
        self.assertNotEqual(p.returncode, 0)
        self.assertTrue(p.stderr.strip(), "says why")
        self.assertEqual(f.read_text(), '{"location": true}\n')

    def test_gg_pref_changes_at_once_all_stay(self):
        env = {**os.environ, "XDG_CONFIG_HOME": str(self.dir)}
        keys = [f"dock.k{i}" for i in range(16)]
        with ThreadPoolExecutor(16) as pool:
            list(pool.map(lambda k: subprocess.run([sys.executable, str(PREF), k, "1"], env=env, check=True), keys))
        saved = json.loads((self.dir / "golden-gate/desktop.json").read_text())
        self.assertEqual(sorted(saved["dock"]), sorted(k.split(".")[1] for k in keys))


class LocationConsent(unittest.TestCase):
    """Location Services fails closed: only a recorded yes turns it on."""
    def test_only_a_recorded_yes(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location("locate", ROOT / "apps/lib/location/locate.py")
        locate = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(locate)
        with tempfile.TemporaryDirectory() as t:
            os.environ["XDG_CONFIG_HOME"] = t
            try:
                self.assertFalse(locate.enabled(), "no choice recorded")
                (Path(t) / "golden-gate").mkdir()
                f = Path(t) / "golden-gate/privacy.json"
                for text, on in (("{not json", False), ("[]", False), ('{"shareDiagnostics": true}', False),
                                 ('{"location": "yes"}', False), ('{"location": false}', False), ('{"location": true}', True)):
                    f.write_text(text)
                    self.assertEqual(locate.enabled(), on, text)
            finally:
                del os.environ["XDG_CONFIG_HOME"]


class Stand(preview.Preview):
    def __init__(self, env, failing=()):
        super().__init__(env, str(ROOT / "apps"), "'default'")
        self.failing = failing
        self.ran = []

    @Slot("QVariant", result="QVariantMap")
    def run(self, cmd):
        cmd = cmd.toVariant() if hasattr(cmd, "toVariant") else cmd
        line = " ".join(str(c) for c in cmd)
        self.ran.append(line)
        if "kb_layout" in line:
            return {"stdout": "kb_layout=ch\nkb_variant=fr\n", "stderr": "", "code": 0}
        if any(f in line for f in self.failing):
            return {"stdout": "", "stderr": "Read-only file system", "code": 1}
        return {"stdout": "", "stderr": "", "code": 0}


class SettingsSys(unittest.TestCase):
    def load(self, failing=()):
        home = Path(tempfile.mkdtemp())
        env = {"HOME": str(home), "XDG_CONFIG_HOME": str(home / ".config")}
        self.stand = Stand(env, failing)
        self.view = QQuickView()
        self.view.engine().addImportPath(str(ROOT / "tools/preview/qml"))
        self.view.engine().rootContext().setContextProperty("__preview", self.stand)
        c = QQmlComponent(self.view.engine())
        c.setData(b'import QtQuick\nimport "../apps/settings"\nSys { objectName: "sys" }',
                  QUrl.fromLocalFile(str(ROOT / "tests" / "SysFixture.qml")))
        self.assertEqual(c.status(), QQmlComponent.Ready, "\n".join(e.toString() for e in c.errors()))
        self.c = c
        self.sys = c.create()
        QTest.qWait(150)

    def value(self, name):
        v = self.sys.property(name)
        return v.toVariant() if hasattr(v, "toVariant") else v

    def call(self, name, *args):
        QMetaObject.invokeMethod(self.sys, name, *[Q_ARG("QVariant", a) for a in args])
        QTest.qWait(250)

    def test_setup_keyboard_variant_survives(self):
        self.load()
        self.assertEqual((self.value("input")["layout"], self.value("input")["variant"]), ("ch", "fr"))
        self.call("setInput", "repeatRate", 40)
        text = self.call_ret("inputConfig")
        self.assertIn("kb_layout = ch", text)
        self.assertIn("kb_variant = fr", text, "the repeat rate doesn't change the keyboard")
        self.assertIn("repeat_rate = 40", text)
        self.assertTrue(any("write-file.py" in l and l.endswith("input.conf") for l in self.stand.ran))

    def call_ret(self, name):
        """A function's return value, through a QML expression."""
        from PySide6.QtQml import QQmlExpression
        e = QQmlExpression(self.view.engine().rootContext(), self.sys, name + "()")
        v = e.evaluate()[0]
        return v.toVariant() if hasattr(v, "toVariant") else v

    def test_a_failed_save_is_reported(self):
        self.load(failing=("write-file.py",))
        self.call("setPrivacy", "location", False)
        self.assertIn("couldn't be saved", self.value("writeError"))
        self.assertIn("privacy.json", self.value("writeError"))

    def test_a_failed_pref_is_reported(self):
        self.load(failing=("gg-pref",))
        self.call("setPref", ["dock", "size"], 60)
        self.assertIn("desktop.json", self.value("writeError"))

    def test_saved_without_fuss(self):
        self.load()
        self.call("setPrivacy", "location", False)
        self.assertEqual(self.value("writeError"), "")


if __name__ == "__main__":
    unittest.main(verbosity=2)
