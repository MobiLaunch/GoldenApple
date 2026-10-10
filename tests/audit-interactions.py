#!/usr/bin/env python3
"""Exercise failures and keyboard paths from the Oct 8 audit in real QML.

System commands are replaced by a Preview service; nothing changes the host.
"""
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
from PySide6.QtCore import QEvent, QObject, QUrl, Qt, Slot
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlExpression, QQmlEngine
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/preview"))
import preview
APP = QGuiApplication([])


class System(preview.Preview):
    def __init__(self, home):
        super().__init__({"HOME": str(home), "USER": "preview", "XDG_CONFIG_HOME": str(home / "config"),
                          "XDG_STATE_HOME": str(home / "state"), "GG_PASSWORDS_PREVIEW": "1"},
                         str(ROOT / "apps"), "'default'")
        self.commands = []
        self.fail_write = False
        self.fail_service = False
        self.fail_draft = False
        self.enabled = True
        self.active = True

    @Slot("QVariant", result="QVariantMap")
    def run(self, cmd):
        cmd = cmd.toVariant() if hasattr(cmd, "toVariant") else cmd
        self.commands.append(cmd)
        result = dict(stdout="", stderr="", code=0)
        if cmd[0] == "nmcli":
            if "connect" in cmd:
                return dict(stdout="", stderr="Connection timed out", code=10)
            return dict(stdout="enabled" if "radio" in cmd else "", stderr="", code=0)
        if cmd[0] == "systemctl":
            if "is-enabled" in cmd:
                result["code"] = 0 if self.enabled else 1
            elif "is-active" in cmd:
                result["code"] = 0 if self.active else 1
            elif self.fail_service:
                result.update(code=1, stderr="Receiver failed")
            elif "disable" in cmd:
                self.enabled = self.active = False
            elif "enable" in cmd or "restart" in cmd:
                self.enabled = self.active = True
            return result
        if any(str(c).endswith("write-file.py") for c in cmd):
            return dict(stdout="", stderr="Read-only filesystem" if self.fail_write else "", code=1 if self.fail_write else 0)
        if cmd[:2] == ["gio", "trash"]:
            return dict(stdout="", stderr="Permission denied", code=1)
        if any(str(c).endswith("passwords/helper.py") for c in cmd):
            return dict(stdout='{"ok":true,"items":[],"wifi":[],"deleted":[],"codes":[]}', stderr="", code=0)
        if any(str(c).endswith("mail/helper.py") for c in cmd):
            if "draft-load" in cmd:
                return dict(stdout='{"ok":true,"draft":{"to":"","subject":"","body":""}}', stderr="", code=0)
            if "draft-save" in cmd:
                return dict(stdout=json.dumps({"ok": not self.fail_draft, "error": "Disk full"}), stderr="", code=1 if self.fail_draft else 0)
        return super().run(cmd)


class Interactions(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.system = System(Path(self.tmp.name))
        self.view = QQuickView()
        self.engine = self.view.engine()
        self.engine.addImportPath(str(ROOT / "tools/preview/qml"))
        self.engine.rootContext().setContextProperty("__preview", self.system)

    def load(self, app=None, pane=None):
        self.component = QQmlComponent(self.engine)
        if pane:
            qml = f'import QtQuick\nimport "../apps/settings"\nimport "../apps/settings/panes"\nItem {{ width: 700; height: 650; Sys {{ id: s }} {pane}Pane {{ objectName: "pane"; width: 650; height: 600; sys: s }} }}'
            url = QUrl.fromLocalFile(str(ROOT / "tests/AuditFixture.qml"))
            self.component.setData(qml.encode(), url)
        else:
            url = QUrl.fromLocalFile(str(ROOT / "tools/preview/Desktop.qml"))
            self.component.loadUrl(url)
        self.assertEqual(self.component.status(), QQmlComponent.Ready, "\n".join(e.toString() for e in self.component.errors()))
        if app:
            self.root = self.component.createWithInitialProperties({"targetUrl": QUrl.fromLocalFile(str(ROOT / "apps" / (app + ".qml")))})
        else:
            self.root = self.component.create()
        self.assertIsNotNone(self.root)
        if pane:
            self.view.setContent(url, self.component, self.root)
            self.view.resize(1000, 800)
            self.view.show(); self.view.requestActivate()
        else:
            self.root.requestActivate()
        QTest.qWait(150)
        return self.root.findChild(QObject, "pane" if pane else app + "App")

    def eval(self, obj, code):
        e = QQmlExpression(QQmlEngine.contextForObject(obj), obj, code)
        v = e.evaluate()[0]
        self.assertFalse(e.hasError(), e.error().toString())
        return v.toVariant() if hasattr(v, "toVariant") else v

    def tearDown(self):
        if hasattr(self, "root") and hasattr(self.root, "close"):
            self.root.close(); self.root.deleteLater()
        self.view.close(); self.view.deleteLater(); APP.processEvents()
        APP.sendPostedEvents(None, QEvent.DeferredDelete)
        self.tmp.cleanup()

    def test_wifi_repeated_join_and_failure(self):
        p = self.load(pane="Wifi")
        self.eval(p, 'join("Home", "secret"); join("Home", "secret")')
        self.assertTrue(p.property("connecting"))
        QTest.qWait(60)
        self.assertEqual(sum("connect" in c for c in self.system.commands), 1)
        self.assertFalse(p.property("connecting"))
        self.assertIn("timed out", p.property("error"))
        self.assertEqual(p.property("joining"), "Home")

    def test_airplay_failed_save_does_not_restart(self):
        p = self.load(pane="AirPlay")
        self.system.fail_write = True
        self.eval(p, 'save({requirePin:false})')
        QTest.qWait(80)
        self.assertTrue(p.property("requirePin"))
        self.assertFalse(p.property("busy"))
        self.assertIn("couldn't be saved", p.property("error"))
        self.assertFalse(any("restart" in c for c in self.system.commands))

    def test_airplay_failed_disable_reconciles_real_state(self):
        p = self.load(pane="AirPlay")
        self.system.fail_service = True
        self.eval(p, "setOn(false)")
        QTest.qWait(80)
        self.assertTrue(p.property("on"))
        self.assertTrue(p.property("active"))
        self.assertIn("Receiver failed", p.property("error"))

    def test_settings_search_keyboard_and_reduced_motion(self):
        p = self.load(app="settings")
        search = self.root.findChild(QObject, "settingsSearch")
        self.assertIsNotNone(search)
        search.setProperty("text", "volume")
        self.eval(search, "input.forceActiveFocus()")
        QTest.keyClick(self.root, Qt.Key_Down)
        QTest.qWait(190)  # Let the 145 ms suggestion enter animation finish.
        self.assertEqual(p.property("selectedMatch"), 0)
        self.assertTrue(self.root.findChild(QObject, "settingsSuggestions").property("visible"))
        QTest.keyClick(self.root, Qt.Key_Return)
        QTest.qWait(300)
        self.assertEqual(p.property("current"), "sound")
        self.assertEqual(search.property("text"), "")
        self.eval(p, 'Theme.reduceMotion = true; open("trackpad")')
        loader = self.root.findChild(QObject, "settingsPaneLoader")
        self.assertEqual(loader.property("x"), 0)
        self.assertEqual(loader.property("opacity"), 1)
        self.assertEqual(loader.property("shown"), "trackpad")

    def test_password_edit_survives_lock_and_navigation_asks(self):
        p = self.load(app="passwords")
        self.eval(p, 'startNewNow("code"); draft.title = "Keep my edit"; draft.totp = "JBSWY3DPEHPK3PXP"; select("other")')
        self.assertTrue(p.property("confirmLeave"))
        self.assertEqual(p.property("selectedId"), "new")
        keep = self.root.findChild(QObject, "keepPasswordEdit")
        self.assertEqual(self.root.activeFocusItem(), keep)
        for _ in range(3):
            QTest.keyClick(self.root, Qt.Key_Tab)
        self.assertEqual(self.root.activeFocusItem(), keep)
        QTest.keyClick(self.root, Qt.Key_Escape)
        self.assertFalse(p.property("confirmLeave"))
        self.assertEqual(self.eval(p, "draft.title"), "Keep my edit")
        self.eval(p, 'select("other")')
        self.eval(p, "lock()")
        self.assertTrue(p.property("locked"))
        self.assertTrue(p.property("editing"))
        self.assertEqual(self.eval(p, "draft.title"), "Keep my edit")
        self.eval(p, "unlocked()")
        QTest.qWait(50)
        self.assertEqual(self.eval(p, "draft.title"), "Keep my edit")

    def test_password_edit_waits_for_secret(self):
        p = self.load(app="passwords")
        self.eval(p, 'items = [{id:"test",kind:"website",title:"example.com",origin:"https://example.com",username:"me"}]; selectedId="test"; secret=({}); startEdit()')
        self.assertFalse(p.property("editing"))
        self.eval(p, 'secret = {ok:true,password:"Keep this",notes:"",totp:""}; startEdit()')
        self.assertTrue(p.property("editing"))
        self.assertEqual(self.eval(p, "draft.password"), "Keep this")

    def test_keyboard_typing_resets_password_idle_timer(self):
        p = self.load(app="passwords")
        self.eval(p, 'startNewNow("code")')
        # Use the actual focused TextInput signal, not a direct activity call.
        self.eval(p, 'lockTimer.interval = 180; activity()')
        field = self.root.findChild(QObject, "draftWebsite")
        self.assertIsNotNone(field)
        self.eval(field, "input.forceActiveFocus()")
        for _ in range(4):
            QTest.qWait(80)
            QTest.keyClick(self.root, Qt.Key_X)
            self.assertFalse(p.property("locked"))
        QTest.qWait(230)
        self.assertTrue(p.property("locked"))

    def test_photos_trash_failure_keeps_item(self):
        p = self.load(app="photos")
        self.eval(p, 'items = [{path:"/readonly/picture.png",name:"picture.png",kind:"photo",mtime:1}]; trash(items[0])')
        QTest.qWait(60)
        self.assertEqual(self.eval(p, "items.length"), 1)
        self.assertIn("Permission denied", p.property("notice"))

    def test_mail_failed_close_save_keeps_draft_open(self):
        p = self.load(app="mail")
        self.assertTrue(p.property("draftReady"))
        self.system.fail_draft = True
        self.eval(p, 'composeBody = "Do not lose this message"; requestClose()')
        self.assertTrue(p.property("closing"))
        QTest.qWait(60)
        self.assertFalse(p.property("closing"))
        self.assertEqual(p.property("composeBody"), "Do not lose this message")
        self.assertIn("Disk full", p.property("error"))

    def test_settings_action_row_keyboard(self):
        self.component = QQmlComponent(self.engine)
        url = QUrl.fromLocalFile(str(ROOT / "tests/AuditFixture.qml"))
        self.component.setData(b'''import QtQuick
import "../apps/settings"
Item { width: 500; height: 100; property int actions: 0
    SetRow { objectName: "actionRow"; title: "Open"; chevron: true; onClicked: parent.actions++ }
}''', url)
        self.assertEqual(self.component.status(), QQmlComponent.Ready,
                         "\n".join(e.toString() for e in self.component.errors()))
        self.root = self.component.create()
        self.view.setContent(url, self.component, self.root)
        self.view.show(); self.view.requestActivate()
        row = self.root.findChild(QObject, "actionRow")
        row.forceActiveFocus()
        self.assertTrue(row.property("activeFocus"))
        QTest.keyClick(self.view, Qt.Key_Space)
        QTest.keyClick(self.view, Qt.Key_Return)
        self.assertEqual(self.root.property("actions"), 2)
        row.setProperty("enabled", False)
        QTest.keyClick(self.view, Qt.Key_Space)
        self.assertEqual(self.root.property("actions"), 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
