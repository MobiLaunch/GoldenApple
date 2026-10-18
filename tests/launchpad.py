#!/usr/bin/env python3
"""Launchpad (shell/Applications.qml), loaded in Qt with isolated services:
its grid, paging, search, keyboard and folders. Reuses the Focus harness.
"""
import importlib.util
import os
from pathlib import Path
import unittest
from PySide6.QtCore import QEvent, Qt, QUrl
from PySide6.QtGui import QKeyEvent
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('focus_harness', ROOT / 'tests/focus-ui.py')
harness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harness)


class Launchpad(harness.Harness):
    def desktop(self, target, name, width=1440, height=900):
        self.system._env['GG_WALLPAPER'] = str(ROOT / 'tools/preview/cache/tide.png')
        # Set the screen before loading. The preview takes a screen snapshot
        # at construction, just as each production surface is given a screen.
        self.engine.setInitialProperties({'targetUrl': QUrl.fromLocalFile(str(ROOT / target)),
                                          'screenWidth': width, 'screenHeight': height})
        self.engine.load(QUrl.fromLocalFile(str(ROOT / 'tools/preview/Desktop.qml')))
        self.assertTrue(self.engine.rootObjects())
        self.root = self.engine.rootObjects()[0]
        QTest.qWait(50)
        obj = self.find(name)
        self.assertIsNotNone(obj, 'Production ' + target + ' failed to load')
        return obj
    def test_launchpad_close_during_preparation_never_reopens_or_captures_input(self):
        apps = self.desktop('tests/fixtures/launch-surfaces.qml', 'launchpad')
        self.eval(apps, 'present(); dismiss()')
        QTest.qWait(230)
        self.assertEqual(apps.property('warmFrames'), 0)
        self.assertEqual(apps.property('reveal'), 0)
        self.assertFalse(apps.property('showing'))
        self.assertEqual(self.eval(apps, 'mask.item.width * mask.item.height'), 0)
        self.eval(apps, 'present()')
        QTest.qWait(230)
        self.assertEqual(apps.property('reveal'), 1)

    def test_launchpad_reference_grid_and_search(self):
        apps = self.desktop('tests/fixtures/launch-surfaces.qml', 'launchpad', width=1536, height=998)
        self.eval(apps, 'present()')
        QTest.qWait(300)
        self.assertEqual(apps.property('columns'), 8)
        self.assertEqual(apps.property('rows'), 5)
        search = self.find('launchpadSearch')
        self.assertEqual(search.property('radius'), search.property('height') / 2)
        self.assertGreater(apps.property('bottomClearance'), 54 + 22, 'room below the dots for the Dock')
        grid = self.find('launchpadGrid')   # in Launchpad's own scope, beside its backdrop
        menu = 'apps.showAppMenu(apps.entries[0], backdrop, 0, 0); JSON.stringify(apps.contextItems.map(i => i.label || i))'
        labels = self.eval(grid, menu)
        self.assertEqual(labels, '["Open","Open New Window"]', 'no Dock items without a Dock to pin to')
        self.eval(grid, 'appMenu.open = false; apps.dock = { iconSize: 54, pins: [], isPinned(id) { return this.pins.includes(id) }, setPinned(id, on) { this.pins = on ? this.pins.concat([id]) : [] } }')
        self.eval(grid, 'apps.showAppMenu(apps.entries[0], backdrop, 0, 0); apps.contextItems[3].action()')
        self.assertEqual(self.eval(apps, 'dock.pins[0] === entries[0].id'), True, "Add to Dock pins the app in MacShell's Dock")
        self.assertEqual(self.eval(grid, menu), '["Open","Open New Window","-","Remove from Dock"]')

    def test_launchpad_reference_positions_and_common_laptop_grid(self):
        apps = self.desktop('tests/fixtures/launch-surfaces.qml', 'launchpad', width=1536, height=998)
        self.eval(apps, 'present()')
        QTest.qWait(300)
        search = self.find('launchpadSearch')
        self.assertAlmostEqual(search.property('width'), 244)
        self.assertAlmostEqual(search.property('y'), 51)
        first = self.find('launchpadIcon:org.goldengate.Files')
        center = self.eval(first, 'mapToItem(null,width/2,height/2)')
        self.assertAlmostEqual(center.x(), 256.125, delta=1)
        self.assertAlmostEqual(center.y(), 176, delta=1)
        for width, height in ((1366, 768), (1280, 720), (1920, 1080)):
            self.eval(self.root, f'screenWidth={width}; screenHeight={height}')
            # The fixture screen is a snapshot; resize the surface directly.
            self.eval(apps, f'width={width}; height={height}')
            self.assertEqual(apps.property('columns'), 8)
            self.assertEqual(apps.property('rows'), 5)

    def test_launchpad_fade_keeps_icons_stationary_and_catalog_stable(self):
        apps = self.desktop('tests/fixtures/launch-surfaces.qml', 'launchpad', width=1536, height=998)
        self.eval(apps, 'present()')
        QTest.qWait(15)
        grid = self.find('launchpadGrid')
        first = self.find('launchpadIcon:org.goldengate.Files')
        center = self.eval(first, 'mapToItem(null,width/2,height/2)')
        entries = self.eval(apps, 'entries.map(e=>e.id).join()')
        for _ in range(15):
            self.eval(apps, 'present()')
            QTest.qWait(15)
            self.assertEqual(grid.property('scale'), 1)
            self.assertEqual(self.eval(first, 'mapToItem(null,width/2,height/2)'), center)
            self.assertIs(first, self.find('launchpadIcon:org.goldengate.Files'))
        self.eval(apps, 'approvedIcons={}; iconCatalogReady=false')
        self.assertEqual(self.eval(apps, 'entries.map(e=>e.id).join()'), entries)
        apps.setProperty('query', 'Music')
        QTest.qWait(30)
        filtered = self.eval(apps, 'entries.map(e=>e.id).join()')
        self.eval(apps, 'dismiss()')
        self.assertEqual(self.eval(apps, 'entries.map(e=>e.id).join()'), filtered)
        self.eval(apps, 'present()')
        QTest.qWait(220)
        self.assertTrue(apps.property('visible'))
        self.assertEqual(apps.property('reveal'), 1)
        self.eval(apps, 'dismiss()')
        QTest.qWait(220)
        self.assertEqual(apps.property('query'), '')
        self.assertTrue(apps.property('visible'), 'the ready Wayland window stays mapped')
        self.assertFalse(apps.property('showing'))
        self.assertFalse(self.find('launchpadSearch').property('visible'))
        self.assertFalse(grid.property('visible'))
        self.assertEqual(self.eval(apps, 'mask.item.width * mask.item.height'), 0)

    def test_launchpad_reduce_motion_stops_an_active_fade(self):
        apps = self.desktop('tests/fixtures/launch-surfaces.qml', 'launchpad')
        self.eval(apps, 'present()')
        QTest.qWait(30)
        self.assertLess(apps.property('reveal'), 1)
        self.eval(self.find('launchSurfacesFixture'), 'motion(true)')
        self.assertEqual(apps.property('reveal'), 1)
        self.eval(apps, 'dismiss()')
        self.assertEqual(apps.property('reveal'), 0)

    def test_launchpad_wheel_burst_changes_one_page(self):
        apps = self.desktop('tests/fixtures/launch-surfaces.qml', 'launchpad')
        self.eval(apps, 'present(); sessionHome=Array.from({length:120}, (_,i)=>({id:"fixture."+i,name:"App "+i,icon:"org.goldengate.Files"}))')
        QTest.qWait(220)
        grid = self.find('launchpadGrid')
        turn = 'pageWheel({pixelDelta:{x:0,y:0},angleDelta:{x:0,y:-120}})'
        self.eval(apps, turn)
        self.assertEqual(grid.property('currentIndex'), 1)
        for _ in range(8):
            self.eval(apps, turn)
        self.assertEqual(grid.property('currentIndex'), 1)
        QTest.qWait(420)
        self.eval(apps, turn)
        self.assertEqual(grid.property('currentIndex'), 2)

    def test_reference_renders(self):
        folder = os.environ.get('GG_UI_REVIEW_SHOTS')
        if not folder:
            self.skipTest('optional review captures')
        target = Path(folder)
        target.mkdir(parents=True, exist_ok=True)
        apps = self.desktop('tests/fixtures/launch-surfaces.qml', 'launchpad', width=1536, height=998)
        self.eval(apps, 'present()')
        QTest.qWait(400)
        self.assertTrue(self.root.grabWindow().save(str(target / 'launchpad.png')))

    def test_launchpad_keyboard_pages_search_and_single_activation(self):
        apps = self.desktop('tests/fixtures/launch-surfaces.qml', 'launchpad')
        self.eval(apps, 'present(); sessionHome=Array.from({length:90}, (_,i)=>({id:"fixture."+i,name:"App "+i,icon:"org.goldengate.Files",execute:()=>{contextX++}})); sessionCatalog=sessionHome')
        QTest.qWait(220)
        self.root.requestActivate()
        QTest.keyClick(self.root, Qt.Key_Down)
        self.assertTrue(self.find('launchpadCell:fixture.0').property('activeFocus'))
        QTest.keyClick(self.root, Qt.Key_Down)
        self.assertEqual(apps.property('focusIndex'), apps.property('columns'))
        # Navigate across the lazy page boundary, then back to the first tile.
        QTest.keyClick(self.root, Qt.Key_End)
        QTest.qWait(450)
        self.assertTrue(self.find('launchpadCell:fixture.89').property('activeFocus'))
        self.assertEqual(self.find('launchpadGrid').property('currentIndex'), 2)
        QTest.keyClick(self.root, Qt.Key_Home)
        QTest.qWait(450)
        self.assertTrue(self.find('launchpadCell:fixture.0').property('activeFocus'))
        # Offscreen QTest.keyClick does not apply a keyboard layout to text.
        harness.APP.sendEvent(self.root, QKeyEvent(QEvent.KeyPress, Qt.Key_A, Qt.ShiftModifier, 'A'))
        harness.APP.sendEvent(self.root, QKeyEvent(QEvent.KeyRelease, Qt.Key_A, Qt.ShiftModifier, 'A'))
        self.assertEqual(apps.property('query'), 'A')
        QTest.keyClick(self.root, Qt.Key_Escape)
        self.assertEqual(apps.property('query'), '')
        self.assertTrue(apps.property('open'))
        QTest.keyClick(self.root, Qt.Key_Down)
        QTest.keyClick(self.root, Qt.Key_Return)
        self.assertEqual(apps.property('contextX'), 1)
        self.assertFalse(apps.property('open'))
        QTest.qWait(220)
        self.eval(apps, 'present()')
        QTest.qWait(220)
        QTest.keyClick(self.root, Qt.Key_Escape)
        self.assertFalse(apps.property('open'))

    def test_launchpad_folder_escape_restores_origin_and_scrolls_focus(self):
        apps = self.desktop('tests/fixtures/launch-surfaces.qml', 'launchpad')
        self.eval(apps, 'present(); sessionHome=[{id:"folder:test",name:"Test Folder",isFolder:true,apps:Array.from({length:24},(_,i)=>({id:"folderapp."+i,name:"Folder App "+i,icon:"org.goldengate.Files",execute:()=>{contextX++}}))}]')
        QTest.qWait(220)
        self.root.requestActivate()
        QTest.keyClick(self.root, Qt.Key_Down)
        QTest.keyClick(self.root, Qt.Key_Return)
        QTest.qWait(250)
        self.assertTrue(self.find('launchpadFolderCell:folderapp.0').property('activeFocus'))
        QTest.keyClick(self.root, Qt.Key_Right)
        self.assertTrue(self.find('launchpadFolderCell:folderapp.1').property('activeFocus'))
        QTest.keyClick(self.root, Qt.Key_End)
        last = self.find('launchpadFolderCell:folderapp.23')
        self.assertTrue(last.property('activeFocus'))
        self.assertTrue(self.eval(last, 'mapToItem(parent.parent,0,0).y + height <= parent.parent.height'))
        QTest.keyClick(self.root, Qt.Key_Escape)
        QTest.qWait(220)
        self.assertTrue(apps.property('open'))
        self.assertTrue(self.find('launchpadCell:folder:test').property('activeFocus'))
        QTest.keyClick(self.root, Qt.Key_Return)
        QTest.qWait(220)
        QTest.keyClick(self.root, Qt.Key_Space)
        self.assertEqual(apps.property('contextX'), 1)
        self.assertFalse(apps.property('open'))


if __name__ == '__main__':
    unittest.main(verbosity=2)
