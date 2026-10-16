#!/usr/bin/env python3
"""Settings' preference files: every one is replaced whole and atomically
(apps/settings/write-file.py), a failed write leaves the old file and is
reported in the window; gg-pref changes made at the same moment all stay;
and the keyboard variant Setup chose (such as ch(fr)) survives a change of
repeat rate.

privacy, input and accessibility change key by key (set-prefs.py): two
Settings windows with their own (stale) copies each keep their change; a
damaged record is refused, not replaced; input.conf and accessibility.conf
are written with their record or not at all; a change is applied to the
running session only once saved, and one the session refuses is reported
as saved but not applied."""
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
SETTER = ROOT / "apps/settings/set-prefs.py"


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

    def test_gg_pref_leaves_a_damaged_file(self):
        env = {**os.environ, "XDG_CONFIG_HOME": str(self.dir)}
        f = self.dir / "golden-gate/desktop.json"
        f.parent.mkdir()
        f.write_text('{"dock": {"size": 60}, "wallp')
        p = subprocess.run([sys.executable, str(PREF), "dock.size", "70"], env=env, capture_output=True, text=True)
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(f.read_text(), '{"dock": {"size": 60}, "wallp', "not replaced by a fresh {}")


class Records(unittest.TestCase):
    """set-prefs.py on its own."""
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.env = {**os.environ, "XDG_CONFIG_HOME": str(self.dir)}

    def tearDown(self):
        self.tmp.cleanup()

    def set(self, record, *pairs):
        p = subprocess.run([sys.executable, str(SETTER), record, *pairs], env=self.env, capture_output=True, text=True)
        return json.loads(p.stdout), p.returncode

    def read(self, name):
        return json.loads((self.dir / "golden-gate" / name).read_text())

    def test_changes_at_once_all_stay(self):
        keys = [f"k{i}" for i in range(16)]
        with ThreadPoolExecutor(16) as pool:
            list(pool.map(lambda k: self.set("privacy", f"{k}=true"), keys))
        self.assertEqual(sorted(self.read("privacy.json")), sorted(keys))
        with ThreadPoolExecutor(8) as pool:
            list(pool.map(lambda kv: self.set("input", kv), ["repeatRate=40", "repeatDelay=300", "tapToClick=false",
                                                            "naturalScroll=false", "sensitivity=0.5", 'layout="de"']))
        i = self.read("input.json")
        self.assertEqual((i["repeatRate"], i["repeatDelay"], i["tapToClick"], i["layout"]), (40, 300, False, "de"))
        conf = (self.dir / "hypr/golden-gate/input.conf").read_text()
        for line in ("kb_layout = de", "repeat_rate = 40", "repeat_delay = 300", "tap-to-click = false",
                     "natural_scroll = false", "sensitivity = 0.50"):
            self.assertIn(line, conf, "the .conf is the merged record, not one writer's")

    def test_only_the_keys_given(self):
        (self.dir / "golden-gate").mkdir()
        (self.dir / "golden-gate/privacy.json").write_text('{"location": true, "other": [1, 2]}')
        r, code = self.set("privacy", "shareDiagnostics=false")
        self.assertEqual(code, 0)
        self.assertEqual(r["record"], {"location": True, "other": [1, 2], "shareDiagnostics": False})

    def test_a_damaged_record_is_refused(self):
        (self.dir / "golden-gate").mkdir()
        f = self.dir / "golden-gate/privacy.json"
        for text in ('{"location": tr', "[1]", "42"):
            f.write_text(text)
            r, code = self.set("privacy", "location=false")
            self.assertNotEqual(code, 0)
            self.assertIn("damaged", r["error"])
            self.assertEqual(f.read_text(), text)

    def test_conf_and_record_go_together(self):
        self.set("input", "repeatRate=30")
        before = (self.dir / "golden-gate/input.json").read_text()
        conf = self.dir / "hypr/golden-gate/input.conf"
        old = conf.read_text()
        conf.unlink()
        conf.mkdir()                             # input.conf can't be replaced
        (conf / "x").write_text("")
        r, code = self.set("input", "repeatRate=45")
        self.assertNotEqual(code, 0)
        self.assertEqual((self.dir / "golden-gate/input.json").read_text(), before, "the record is put back")
        self.assertIn("repeat_rate = 30", old)

    def test_setup_keyboard_is_kept_the_first_time(self):
        conf = self.dir / "hypr/golden-gate/input.conf"
        conf.parent.mkdir(parents=True)
        conf.write_text("input {\n    kb_layout = ch\n    kb_variant = fr\n}\n")
        r, _ = self.set("input", "repeatRate=40")
        self.assertEqual((r["record"]["layout"], r["record"]["variant"]), ("ch", "fr"))
        self.assertIn("kb_variant = fr", conf.read_text())

    def test_accessibility_conf(self):
        self.set("accessibility", "reduceMotion=true")
        self.assertIn("enabled = false", (self.dir / "hypr/golden-gate/accessibility.conf").read_text())
        self.set("accessibility", "reduceMotion=false")
        self.assertIn("enabled = true", (self.dir / "hypr/golden-gate/accessibility.conf").read_text())

    def test_bad_arguments(self):
        self.assertNotEqual(self.set("privacy", "no-equals")[1], 0)
        self.assertNotEqual(self.set("privacy", "../x=1")[1], 0)
        self.assertNotEqual(self.set("passwords", "a=1")[1], 0)


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
    """set-prefs.py runs for real, in this stand's home; hyprctl answers as
    told (refusing: as Hyprland does a keyword it won't take)."""
    def __init__(self, env, failing=(), refusing=False):
        super().__init__(env, str(ROOT / "apps"), "'default'")
        self.home_env = env
        self.failing = failing
        self.refusing = refusing
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
        if "set-prefs.py" in line:
            p = subprocess.run([sys.executable, *[str(c) for c in cmd[1:]]], env={**os.environ, **self.home_env},
                               capture_output=True, text=True)
            return {"stdout": p.stdout, "stderr": p.stderr, "code": p.returncode}
        if cmd[:2] == ["hyprctl", "keyword"] and self.refusing:
            return {"stdout": "invalid field: input:repeat_rate", "stderr": "", "code": 0}
        return {"stdout": "ok", "stderr": "", "code": 0}


class SettingsSys(unittest.TestCase):
    def load(self, failing=(), refusing=False, home=None):
        home = home or Path(tempfile.mkdtemp())
        self.home = home
        env = {"HOME": str(home), "XDG_CONFIG_HOME": str(home / ".config")}
        if hasattr(self, "view"):
            self.kept = getattr(self, "kept", []) + [(self.view, self.c, self.sys, self.stand)]   # another window stays open
        self.stand = Stand(env, failing, refusing)
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
        return self.sys

    def value(self, name, sys_=None):
        v = (sys_ or self.sys).property(name)
        return v.toVariant() if hasattr(v, "toVariant") else v

    def call(self, name, *args, sys_=None, wait=400):
        QMetaObject.invokeMethod(sys_ or self.sys, name, *[Q_ARG("QVariant", a) for a in args])
        QTest.qWait(wait)

    def saved(self, name):
        return json.loads((self.home / ".config/golden-gate" / name).read_text())

    def test_setup_keyboard_variant_survives(self):
        self.load()
        self.assertEqual((self.value("input")["layout"], self.value("input")["variant"]), ("ch", "fr"))
        conf = self.home / ".config/hypr/golden-gate/input.conf"
        conf.parent.mkdir(parents=True)
        conf.write_text("input {\n    kb_layout = ch\n    kb_variant = fr\n}\n")
        self.call("setInput", "repeatRate", 40)
        text = conf.read_text()
        self.assertIn("kb_layout = ch", text)
        self.assertIn("kb_variant = fr", text, "the repeat rate doesn't change the keyboard")
        self.assertIn("repeat_rate = 40", text)
        self.assertTrue(any(l.startswith("hyprctl keyword input:repeat_rate 40") for l in self.stand.ran))

    def test_two_windows_keep_both_changes(self):
        a = self.load()
        b = self.load(home=self.home)            # a second Settings, with its own copy
        self.call("setPrivacy", "location", False, sys_=a, wait=0)
        self.call("setPrivacy", "shareDiagnostics", True, sys_=b, wait=0)
        self.call("setInput", "repeatRate", 40, sys_=b, wait=0)
        self.call("setInput", "tapToClick", False, sys_=a)
        self.assertEqual(self.saved("privacy.json"), {"location": False, "shareDiagnostics": True})
        i = self.saved("input.json")
        self.assertEqual((i["repeatRate"], i["tapToClick"]), (40, False))
        self.assertIs(self.value("privacy", a)["location"], False, "each window shows the record as saved")
        self.assertIs(self.value("privacy", b)["shareDiagnostics"], True)

    def test_applied_only_once_saved(self):
        self.load(failing=("set-prefs.py",))
        self.call("setInput", "repeatRate", 40)
        self.assertIn("couldn't be saved", self.value("writeError"))
        self.assertFalse(any(l.startswith("hyprctl keyword") for l in self.stand.ran), "nothing applied that isn't saved")

    def test_saved_but_not_applied(self):
        self.load(refusing=True)
        self.call("setInput", "repeatRate", 40)
        self.assertEqual(self.saved("input.json")["repeatRate"], 40)
        self.assertIn("saved, but it couldn't be applied now", self.value("writeError"))
        self.assertIn("next time you sign in", self.value("writeError"))

    def test_reduce_motion_is_saved_and_acknowledged(self):
        self.load()
        from PySide6.QtQml import QQmlExpression
        QQmlExpression(self.view.engine().rootContext(), self.sys, 'setRecord("accessibility", "reduceMotion", true)').evaluate()
        QTest.qWait(400)
        self.assertIn("enabled = false", (self.home / ".config/hypr/golden-gate/accessibility.conf").read_text())
        self.assertEqual(self.value("writeError"), "")

    def test_a_failed_save_is_reported(self):
        self.load(failing=("set-prefs.py",))
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
