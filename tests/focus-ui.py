#!/usr/bin/env python3
"""Real Focus Settings/Control Center and notification delivery, isolated from host services."""
import json
import os
import re
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
from PySide6.QtCore import QEvent, QObject, QPointF, QUrl, Qt, Slot
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine, QQmlComponent, QQmlEngine, QQmlExpression
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools/preview"))
import preview
APP = QGuiApplication([])


class System(preview.Preview):
    def __init__(self, home):
        self.home_env={"HOME":str(home),"XDG_CONFIG_HOME":str(home/"config"),"XDG_STATE_HOME":str(home/"state")}
        super().__init__(self.home_env,str(ROOT/"shell"),"'default'")
        self.fail=False
        self.commands=[]
        self.logs=[]
    @Slot(str)
    def log(self, text): self.logs.append(text)
    @Slot("QVariant",result="QVariantMap")
    def run(self, cmd):
        cmd=cmd.toVariant() if hasattr(cmd,"toVariant") else cmd
        self.commands.append(cmd)
        if cmd and cmd[0]=="gg-pref":
            if self.fail: return dict(stdout="",stderr="disk full",code=1)
            r=subprocess.run([sys.executable,str(ROOT/"apps/setup/pref-helper.py"),*cmd[1:]],
                             env={**os.environ,**self.home_env},capture_output=True,text=True)
            return dict(stdout=r.stdout,stderr=r.stderr,code=r.returncode)
        # This suite never runs arbitrary commands from the desktop. All
        # services are fixtures; only the preference writer above runs, and
        # it is confined to this test's temporary configuration directory.
        line=" ".join(str(c) for c in cmd)
        for pattern, out, code in preview.FIXTURES:
            if re.search(pattern,line):
                return dict(stdout=out.replace("{scheme}","'default'"),stderr="",code=0 if code=="hang" else code,hang=code=="hang")
        return dict(stdout="",stderr="",code=0)


class Harness(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.home=Path(self.tmp.name)
        self.system=System(self.home)
        self.engine=QQmlApplicationEngine()
        self.interceptor=preview.SingletonDirs()
        self.engine.addUrlInterceptor(self.interceptor)
        self.engine.addImportPath(str(ROOT/"tools/preview/qml"))
        self.engine.rootContext().setContextProperty("__preview",self.system)
        self.root=None
        self.view=None
    def tearDown(self):
        if self.root: self.root.deleteLater()
        if self.view: self.view.deleteLater()
        self.engine.deleteLater()
        APP.processEvents(); APP.sendPostedEvents(None,QEvent.DeferredDelete)
        self.tmp.cleanup()
    def eval(self, obj, code):
        e=QQmlExpression(QQmlEngine.contextForObject(obj),obj,code)
        result=e.evaluate()[0]
        self.assertFalse(e.hasError(),e.error().toString())
        return result.toVariant() if hasattr(result,"toVariant") else result
    def wait_for(self, obj, expression):
        for _ in range(200):
            if self.eval(obj,expression): return
            QTest.qWait(10)
        self.fail("Timed out waiting for " + expression)
    def find(self, name):
        stack=[self.root]; seen=set()
        while stack:
            obj=stack.pop()
            if obj in seen: continue
            seen.add(obj)
            if obj.objectName()==name: return obj
            stack.extend(obj.children())
            if hasattr(obj,"childItems"): stack.extend(obj.childItems())
    def desktop(self, target, name):
        self.engine.setInitialProperties({"targetUrl":QUrl.fromLocalFile(str(ROOT/target))})
        self.engine.load(QUrl.fromLocalFile(str(ROOT/"tools/preview/Desktop.qml")))
        self.assertTrue(self.engine.rootObjects())
        self.root=self.engine.rootObjects()[0]
        self.assertIsNotNone(self.root)
        QTest.qWait(50)
        obj=self.find(name)
        self.assertIsNotNone(obj,"Production " + target + " failed to load")
        return obj


SETTINGS='''import QtQuick
import "../apps/settings/panes" as Panes
import "../apps/lib/theme"
Rectangle {
    id: root; width: 480; height: 580; color: Theme.windowBg
    QtObject {
        id: fake; objectName: "system"
        property var prefs: ({})
        property bool fail: false
        property bool hang: false
        property string writeError: ""
        property var command: []
        function setIn(obj, path, value) {
            const copy = JSON.parse(JSON.stringify(obj)), last = path.pop()
            let node = copy
            for (const key of path) node = node[key] = Object.assign({}, node[key] ?? {})
            node[last] = value; return copy
        }
        function failed(what, why) { writeError = what + ": " + why }
        function run(args, done) { command = args; if (!hang) done("", fail ? 1 : 0, "disk full") }
    }
    Panes.FocusPane { anchors.fill: parent; sys: fake; nav: ({overlay:root}) }
}'''


class Settings(Harness):
    def setUp(self):
        super().setUp()
        self.view=QQuickView(self.engine,None)
        self.component=QQmlComponent(self.engine)
        url=QUrl.fromLocalFile(str(ROOT/"tests/FocusHarness.qml"))
        self.component.setData(SETTINGS.encode(),url)
        self.assertEqual(self.component.status(),QQmlComponent.Ready,"\n".join(e.toString() for e in self.component.errors()))
        self.root=self.component.create()
        self.assertIsNotNone(self.root)
        self.view.setContent(url,self.component,self.root)
        self.view.show(); self.view.requestActivate(); QTest.qWait(20)
        self.pane=self.root.findChild(QObject,"focusPane")
        self.sys=self.root.findChild(QObject,"system")
    def click(self,name):
        obj=self.find(name)
        self.assertIsNotNone(obj)
        obj.forceActiveFocus(); QTest.keyClick(self.view,Qt.Key_Space)
        return obj
    def test_duration_keyboard_save_and_live_expiry(self):
        switch=self.click("focusSwitch")
        session=self.eval(self.pane,"prefs.session")
        self.assertTrue(session["on"])
        self.assertTrue(self.pane.property("dnd"))
        self.assertEqual(self.sys.property("command").toVariant()[1],"focus.session")
        status=self.find("focusState")
        status.setProperty("ticking",False); status.setProperty("now",session["until"])
        self.assertFalse(self.pane.property("dnd"))
        self.assertFalse(switch.property("checked"),"Expiry must update the switch, even after keyboard toggling")
    def test_failed_or_pending_save_does_not_claim_focus_is_on(self):
        self.sys.setProperty("fail",True)
        switch=self.click("focusSwitch")
        self.assertFalse(self.pane.property("dnd"))
        self.assertFalse(switch.property("checked"))
        self.assertIn("disk full",self.sys.property("writeError"))
        self.sys.setProperty("fail",False); self.sys.setProperty("hang",True)
        switch=self.click("focusSwitch")
        self.assertTrue(self.pane.property("saving"))
        self.assertFalse(switch.property("checked"))
        self.assertFalse(switch.property("enabled"))
    def test_schedule_saves_defaults_and_individual_day_changes(self):
        switch=self.click("focusScheduleSwitch")
        saved=self.eval(self.pane,"prefs.schedule")
        self.assertEqual(saved,{"enabled":True,"days":[1,2,3,4,5],"start":1320,"end":420})
        self.assertTrue(switch.property("checked"))
        self.click("focusDay:5")
        self.assertEqual(self.eval(self.pane,"prefs.schedule.days"),[1,2,3,4])
        self.assertEqual(self.sys.property("command").toVariant()[1],"focus.schedule.days")
    def test_app_exception_keys_do_not_become_nested_desktop_ids(self):
        self.click("focusAllow:org.goldengate.clock")
        self.assertEqual(self.eval(self.pane,"prefs.allowedApps"),{"org%2Egoldengate%2Eclock":True})
    def test_large_text_schedule_flows_and_remains_scrollable(self):
        self.eval(self.pane,"Theme.textScale=1.5")
        self.click("focusScheduleSwitch")
        QTest.qWait(20)
        self.assertGreater(self.pane.property("contentHeight"),self.pane.property("height"))
        self.assertTrue(self.pane.property("clip"))
        day=self.find("focusDay:6")
        self.assertGreater(day.property("y"),0,"Days should wrap rather than overflow")
        for index in range(7):
            box=self.find("focusDay:"+str(index))
            stack=list(box.childItems())
            while stack:
                item=stack.pop(); stack.extend(item.childItems())
                if item.property("text")==box.property("text"):
                    self.assertLessEqual(item.property("contentWidth"),item.property("width"),"Day text must not overlap the next checkbox")
        self.eval(self.pane,"Theme.textScale=1")
    def test_keyboard_focus_scrolls_the_end_time_into_view(self):
        self.click("focusScheduleSwitch")
        self.eval(self.pane,"contentY=0")
        end=self.find("focusEnd")
        end.forceActiveFocus(); QTest.qWait(40)
        self.assertGreater(self.pane.property("contentY"),0,"An offscreen keyboard control must scroll into view")
        y=end.mapToItem(self.pane,QPointF(0,0)).y()
        self.assertGreaterEqual(y,0)
        self.assertLessEqual(y+end.property("height"),self.pane.property("height"))


class Notifications(Harness):
    def setUp(self):
        super().setUp()
        self.n=self.desktop("shell/Notifications.qml","notifications")
    def policy(self, p, notification_prefs=None):
        self.eval(self.n,"Prefs.data="+json.dumps({"focus":p,"notifications":notification_prefs or {"sounds":False}}))
    def send(self, app, nid, **extra):
        self.system.notify({"id":nid,"appName":app,"summary":app,"body":"Hello",**extra})
    def names(self, prop="banners"):
        return self.eval(self.n,prop+".map(n=>n.appName)")
    def test_focus_keeps_history_and_shows_only_allowed_app(self):
        self.policy({"session":{"on":True,"until":0},"allowedApps":{"org%2Egoldengate%2Eclock":True}})
        self.send("Clock",1); self.send("Mail",2)
        self.assertEqual(self.names(),["Clock"])
        self.assertEqual(sorted(self.names("list")),["Clock","Mail"])
    def test_disabled_clock_stays_disabled_even_when_focus_allows_it(self):
        self.policy({"session":{"on":True,"until":0},"allowedApps":{"org%2Egoldengate%2Eclock":True}},
                    {"sounds":False,"apps":{"org.goldengate.clock":{"allow":False}}})
        self.send("Clock",1)
        self.assertEqual(self.names(),[])
        self.assertEqual(self.names("list"),[])
    def test_critical_opt_in_still_respects_app_allow_and_banner_settings(self):
        self.policy({"session":{"on":True,"until":0},"allowCritical":True},
                    {"sounds":False,"apps":{"mail":{"allow":False},"calendar":{"banners":False}}})
        self.send("Mail",1,urgency=2); self.send("Calendar",2,urgency=2); self.send("Chat",3,urgency=2); self.send("Other",4)
        self.assertEqual(self.names(),["Chat"])
        self.assertNotIn("Mail",self.names("list"))
    def test_starting_focus_removes_existing_disallowed_banners_without_replay(self):
        self.send("Mail",1); self.send("Clock",2)
        self.policy({"dnd":True,"allowedApps":{"org%2Egoldengate%2Eclock":True}})
        self.assertEqual(self.names(),["Clock"])
        self.policy({"session":{"on":False}})
        self.assertEqual(self.names(),["Clock"],"Silenced banners are not replayed when Focus ends")
    def test_expired_persisted_session_allows_new_banner(self):
        self.policy({"session":{"on":True,"until":1}})
        self.send("Mail",1)
        self.assertEqual(self.names(),["Mail"])
    def test_allowed_app_sounds_follow_focus_and_app_sound_choice(self):
        p={"session":{"on":True,"until":0},"allowedApps":{"org%2Egoldengate%2Eclock":True}}
        self.policy(p,{"sounds":True})
        self.send("Mail",1)
        self.assertFalse(any("pw-play" in line for line in self.system.logs))
        self.send("Clock",2)
        self.assertEqual(sum("pw-play" in line for line in self.system.logs),1)
        self.policy(p,{"sounds":True,"apps":{"clock":{"sound":False}}})
        self.send("Clock",3)
        self.assertEqual(sum("pw-play" in line for line in self.system.logs),1)


class ControlCenter(Harness):
    def test_focus_duration_and_settings_are_keyboard_reachable(self):
        cc=self.desktop("shell/ControlCenter.qml","controlCenter")
        self.eval(cc,"open=true")
        self.root.requestActivate()
        capsule=self.find("ccFocus"); capsule.forceActiveFocus()
        QTest.keyClick(self.root,Qt.Key_Space)
        self.assertEqual(cc.property("detail"),"focus")
        button=self.find("ccFocusDuration:15"); button.forceActiveFocus()
        QTest.keyClick(self.root,Qt.Key_Space); self.wait_for(cc,"!Prefs.focusBusy")
        self.assertTrue(self.eval(cc,"Prefs.focusDnd"))
        button=self.find("ccDetailSettings"); button.forceActiveFocus()
        QTest.keyClick(self.root,Qt.Key_Return)
        self.assertFalse(cc.property("open"))
    def test_duration_saves_real_record_and_failed_write_reports_error(self):
        cc=self.desktop("shell/ControlCenter.qml","controlCenter")
        self.eval(cc,'open=true; showDetail("focus"); Prefs.setFocus(60)')
        self.wait_for(cc,"!Prefs.focusBusy")
        self.assertTrue(self.eval(cc,"Prefs.focusDnd"))
        self.assertIn("Until ",self.eval(cc,"Prefs.focusSummary"))
        self.assertEqual(cc.property("detail"),"focus")
        saved=json.loads((self.home/"config/golden-gate/desktop.json").read_text())
        self.assertTrue(saved["focus"]["session"]["on"])
        self.system.fail=True
        self.eval(cc,"Prefs.setFocus(-1)"); self.wait_for(cc,"!Prefs.focusBusy")
        self.assertTrue(self.eval(cc,"Prefs.focusDnd"))
        self.assertIn("disk full",self.eval(cc,"Prefs.focusError"))


if __name__ == "__main__": unittest.main(verbosity=2)
