#!/usr/bin/env python3
"""Offscreen Qt regression tests; no Quickshell/system services are launched.
Run: QT_QPA_PLATFORM=offscreen python tests/native-controls.py
Requires PySide6-Essentials (Qt >= 6.9).
"""
import os
os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
os.environ.setdefault('QT_QUICK_BACKEND', 'software')
import unittest
from pathlib import Path
from PySide6.QtCore import QObject, QUrl, Qt, QPoint
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest, QSignalSpy

ROOT = Path(__file__).resolve().parents[1]
APP = QGuiApplication([])
QML = '''import QtQuick
import "../apps/lib" as GG
import "../apps/lib/theme"
Rectangle {
    width: 520; height: 370; color: Theme.windowBg
    property int actions: 0
    function dark() { Theme.dark = true }
    function reduce() { Theme.reduceMotion = true }
    function standardMotion() { Theme.reduceMotion = false }
    function showMenu() { menu.popup(button, 0, 30, [
        {text: "First", action: () => actions++}, {separator: true},
        {text: "Disabled", enabled: false}, {text: "Last", action: () => actions += 10}
    ]) }
    GG.Button { id: button; objectName: "button"; x: 30; y: 30; text: "Continue"; prominent: true }
    GG.Checkbox { objectName: "checkbox"; x: 30; y: 80; text: "Show indicators" }
    GG.Switch { objectName: "switch"; x: 250; y: 30; enabled_: false }
    GG.Slider { objectName: "slider"; x: 30; y: 130; width: 220 }
    GG.Segmented { objectName: "segments"; x: 30; y: 185; options: ["Auto", "Light", "Dark"] }
    GG.PopUpButton { objectName: "popupButton"; x: 30; y: 240; options: ["Small", "Medium", "Large"]; menuParent: parent }
    GG.ToolbarButton { objectName: "toolbar"; x: 300; y: 130; text: "Edit" }
    GG.TextField { objectName: "field"; x: 30; y: 295; placeholder: "Regular field"; width: 240 }
    GG.TextField { objectName: "searchField"; x: 290; y: 75; placeholder: "Search"; width: 205; search: true }
    GG.SpringValue { objectName: "spring" }
    GG.SidebarRow { objectName: "sidebarRow"; x: 300; y: 185; width: 180; text: "Inbox"; symbol: "envelope"; selected: true }
    GG.ProgressBar { objectName: "progress"; x: 300; y: 240; width: 180; value: 0.42 }
    GG.EmptyState { objectName: "emptyState"; x: 300; y: 270; width: 190; height: 80; title: "Nothing Here"; text: "Shared empty state" }
    GG.PopupMenu { id: menu; objectName: "menu" }
}'''

class Controls(unittest.TestCase):
    def setUp(self):
        self.view = QQuickView()
        self.component = c = QQmlComponent(self.view.engine())
        url = QUrl.fromLocalFile(str(ROOT / 'tests' / 'Controls.qml'))
        c.setData(QML.encode(), url)
        self.assertEqual(c.status(), QQmlComponent.Ready, '\n'.join(e.toString() for e in c.errors()))
        self.root = c.create()
        self.assertIsNotNone(self.root, '\n'.join(e.toString() for e in c.errors()))
        self.view.setContent(url, c, self.root)
        self.root.standardMotion()
        self.view.show()
        self.view.requestActivate()
        QTest.qWait(30)
    def tearDown(self):
        self.view.close()
        self.view.deleteLater()
        APP.processEvents()
    def control(self, name):
        return self.root.findChild(QObject, name)
    def key(self, obj, key):
        obj.forceActiveFocus()
        QTest.keyClick(self.view, key)
        APP.processEvents()
    def test_buttons_and_checkbox(self):
        for name in ['button', 'toolbar']:
            obj = self.control(name); spy = QSignalSpy(obj.clicked)
            self.key(obj, Qt.Key_Space)
            self.assertEqual(spy.count(), 1)
            obj.setProperty('enabled', False)
            QTest.keyClick(self.view, Qt.Key_Space)
            self.assertEqual(spy.count(), 1)
        box = self.control('checkbox')
        self.key(box, Qt.Key_Space)
        self.assertTrue(box.property('checked'))
        self.assertTrue(box.property('keyboardPressed'))
        QTest.qWait(125)
        self.assertFalse(box.property('keyboardPressed'))
        box.setProperty('enabled',False)
        self.key(box,Qt.Key_Space)
        self.assertTrue(box.property('checked'), 'disabled checkbox cannot toggle')
    def test_disabled_switch_drag_and_keyboard(self):
        sw = self.control('switch'); spy = QSignalSpy(sw.toggled)
        QTest.mousePress(self.view, Qt.LeftButton, pos=QPoint(253, 40))
        QTest.mouseMove(self.view, QPoint(285, 40))
        QTest.mouseRelease(self.view, Qt.LeftButton, pos=QPoint(285, 40))
        self.key(sw, Qt.Key_Space)
        self.assertEqual(spy.count(), 0)
        sw.setProperty('enabled_', True)
        self.key(sw, Qt.Key_Space)
        self.assertTrue(sw.property('checked'))
        self.assertTrue(sw.property('keyboardPressed'))
        QTest.qWait(125)
        self.assertFalse(sw.property('keyboardPressed'))
    def test_slider_endpoints_steps_and_narrow_size(self):
        sl = self.control('slider')
        self.key(sl, Qt.Key_End); self.assertEqual(sl.property('value'), 1)
        self.key(sl, Qt.Key_Home); self.assertEqual(sl.property('value'), 0)
        sl.setProperty('steps', 4)
        self.key(sl, Qt.Key_Right); self.assertEqual(sl.property('value'), .25)
        sl.setProperty('width', 24)
        QTest.mouseClick(self.view, Qt.LeftButton, pos=QPoint(42, 140))
        self.assertEqual(sl.property('value'), .25)
    def test_segment_keyboard(self):
        seg = self.control('segments')
        self.key(seg, Qt.Key_End); self.assertEqual(seg.property('current'), 2)
        self.key(seg, Qt.Key_Left); self.assertEqual(seg.property('current'), 1)
        self.key(seg, Qt.Key_Home); self.assertEqual(seg.property('current'), 0)
    def test_menu_skips_disabled_and_restores_focus(self):
        self.root.showMenu(); APP.processEvents()
        menu = self.control('menu')
        # Opened by the pointer, nothing is highlighted until an arrow key.
        self.assertEqual(menu.property('selected'), -1)
        QTest.keyClick(self.view, Qt.Key_Down)
        self.assertEqual(menu.property('selected'), 0)
        QTest.keyClick(self.view, Qt.Key_Down)
        self.assertEqual(menu.property('selected'), 3)
        QTest.keyClick(self.view, Qt.Key_Return)
        QTest.qWait(500)  # the chosen row flashes, then the menu fades
        self.assertEqual(self.root.property('actions'), 10)
        self.assertFalse(menu.property('visible'))
        self.assertTrue(self.control('button').hasActiveFocus())
    def test_menu_escape_cancels_pending_flash_action(self):
        self.root.showMenu(); APP.processEvents()
        menu=self.control('menu')
        self.assertTrue(menu.property('visible'))
        QTest.keyClick(self.view, Qt.Key_Down)
        QTest.keyClick(self.view, Qt.Key_Return)
        # The Mac-like highlight holds the action briefly. Escape before its
        # completion must not trigger the underlying command after dismissal.
        QTest.keyClick(self.view, Qt.Key_Escape)
        QTest.qWait(260)
        self.assertEqual(self.root.property('actions'),0)
        self.assertFalse(menu.property('visible'))
        self.assertTrue(self.control('button').hasActiveFocus())

    def test_click_away_cancels_pending_menu_action(self):
        self.root.showMenu(); APP.processEvents()
        QTest.keyClick(self.view, Qt.Key_Down)
        QTest.keyClick(self.view, Qt.Key_Return)
        menu=self.control('menu')
        menu.close()
        QTest.qWait(260)
        self.assertEqual(self.root.property('actions'),0)
        self.assertFalse(menu.property('visible'))

    def test_popup_keyboard(self):
        pop = self.control('popupButton')
        self.key(pop, Qt.Key_Space)
        self.assertTrue(pop.property('expanded'), 'popup stays highlighted while its menu is open')
        QTest.keyClick(self.view, Qt.Key_Down)
        QTest.keyClick(self.view, Qt.Key_Return)
        QTest.qWait(500)
        self.assertEqual(pop.property('current'), 1)
        self.assertFalse(pop.property('expanded'))
    def test_shared_sidebar_progress_and_empty_state(self):
        row = self.control('sidebarRow')
        self.assertIsNotNone(row)
        spy = QSignalSpy(row.clicked)
        self.key(row, Qt.Key_Space)
        self.assertEqual(spy.count(), 1)
        self.assertAlmostEqual(self.control('progress').property('value'), 0.42, places=2)
        self.assertEqual(self.control('emptyState').property('title'), 'Nothing Here')

    def test_keyboard_and_accessibility_controls_have_tactile_feedback(self):
        # Pointer presses already light up Liquid Glass; keyboard actions must
        # do the same and then clear their feedback without altering layout.
        for name in ('button','toolbar'):
            obj=self.control(name)
            spy=QSignalSpy(obj.clicked)
            self.key(obj,Qt.Key_Space)
            self.assertEqual(spy.count(),1,name)
            self.assertTrue(obj.property('keyboardPressed'),name)
            QTest.qWait(135)
            self.assertFalse(obj.property('keyboardPressed'),name)
            self.key(obj,Qt.Key_Return)
            self.assertEqual(spy.count(),2,name)
            obj.setProperty('enabled',False)
            self.key(obj,Qt.Key_Space)
            self.assertEqual(spy.count(),2,'disabled controls must never activate')

    def test_segmented_selection_snaps_with_reduce_motion(self):
        seg=self.control('segments')
        pill=seg.findChild(QObject,'segmentedSelectionPill')
        self.assertIsNotNone(pill,'selected glass capsule should be inspectable')
        self.root.reduce()
        seg.setProperty('current',2)
        APP.processEvents()
        at_end=pill.property('x')
        seg.setProperty('current',0)
        APP.processEvents()
        self.assertGreater(at_end, pill.property('x'))
        self.assertAlmostEqual(pill.property('x'),2,delta=1,
                               msg='Reduce Motion must move selection instantly')
        QTest.qWait(80)
        self.assertAlmostEqual(pill.property('x'),2,delta=1)

    def test_disabled_sidebar_ignores_keyboard_and_pointer_activation(self):
        row=self.control('sidebarRow')
        spy=QSignalSpy(row.clicked)
        row.setProperty('enabled',False)
        self.key(row,Qt.Key_Space)
        self.assertEqual(spy.count(),0)
        QTest.mouseClick(self.view,Qt.LeftButton,pos=QPoint(315,198))
        self.assertEqual(spy.count(),0)

    def test_search_clear_affordance_and_escape(self):
        search = self.control('searchField')
        regular = self.control('field')
        search.setProperty('text', 'macOS magic')
        APP.processEvents()
        clear = search.findChild(QObject, 'searchClearButton')
        self.assertIsNotNone(clear)
        self.assertTrue(clear.property('shown'))
        # Mouse and keyboard clear the query without dismissing its parent.
        QTest.mouseClick(self.view, Qt.LeftButton, pos=QPoint(479, 88))
        self.assertEqual(search.property('text'), '')
        search.setProperty('text', 'another query')
        editor = search.property('input')
        editor.forceActiveFocus()
        QTest.keyClick(self.view, Qt.Key_Escape)
        APP.processEvents()
        self.assertEqual(search.property('text'), '')
        self.assertTrue(self.view.isVisible())
        # Plain fields preserve Escape for their dialog/window to handle.
        regular.setProperty('text', 'draft')
        reg_editor = regular.property('input')
        reg_editor.forceActiveFocus()
        QTest.keyClick(self.view, Qt.Key_Escape)
        self.assertEqual(regular.property('text'), 'draft')
        search.setProperty('text', 'quiet')
        self.root.reduce()
        clear = search.findChild(QObject, 'searchClearButton')
        APP.processEvents()
        self.assertAlmostEqual(clear.property('opacity'), 1.0, delta=0.02)
        search.setProperty('text', '')
        APP.processEvents()
        self.assertAlmostEqual(clear.property('opacity'), 0.0, delta=0.02)

    def test_reduce_motion_stops_spring(self):
        spring = self.control('spring')
        spring.setProperty('target', 100)
        self.root.reduce(); APP.processEvents()
        self.assertEqual(spring.property('value'), 100)
        self.assertFalse(spring.property('moving'))
        spring.setProperty('target', 200)
        self.assertEqual(spring.property('value'), 200)
    def test_visual_capture(self):
        folder = os.environ.get('NATIVE_SHOTS')
        if not folder: return
        Path(folder).mkdir(parents=True, exist_ok=True)
        self.control('slider').forceActiveFocus()
        QTest.qWait(200)
        self.assertTrue(self.view.grabWindow().save(str(Path(folder) / 'controls-light.png')))
        self.root.dark(); QTest.qWait(300)
        self.assertTrue(self.view.grabWindow().save(str(Path(folder) / 'controls-dark.png')))

if __name__ == '__main__': unittest.main(verbosity=2)
