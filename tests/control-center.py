#!/usr/bin/env python3
"""Golden Gate rounded shell controls, loaded in Qt with isolated services.
Reuses the existing Focus harness; no host network/audio settings are changed.
"""
import importlib.util
import os
from pathlib import Path
import unittest
from PySide6.QtCore import Qt, QUrl
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('focus_harness', ROOT / 'tests/focus-ui.py')
harness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(harness)


class GoldenGateControls(harness.Harness):
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
    def test_independent_glass_cards_circles_and_vertical_levels(self):
        cc = self.desktop('shell/ControlCenter.qml', 'controlCenter', width=440, height=800)
        self.eval(cc, 'toggle()')
        QTest.qWait(240)
        carrier = self.find('ccPanel')
        self.assertIsNone(carrier.property('role'), 'the carrier is not an enclosing glass box')
        self.assertIsNone(self.find('ccConnectivity').property('role'))
        for name in ('ccWifi', 'ccBluetooth', 'ccAirDrop', 'ccFocus', 'ccMirroring', 'ccNowPlaying'):
            card = self.find(name)
            self.assertGreater(card.property('width'), card.property('height') * 2)
            self.assertEqual(card.property('radius'), card.property('height') / 2)
        for name in ('ccBrightness', 'ccVolume'):
            level = self.find(name)
            self.assertGreater(level.property('height'), level.property('width') * 2)
            self.assertEqual(level.property('radius'), level.property('width') / 2)
        disc = self.find('ccCircle:Dark Mode')
        self.assertEqual(disc.property('width'), disc.property('height'))
        self.assertEqual(disc.property('radius'), disc.property('width') / 2)
        if os.environ.get('GG_UI_REVIEW_SHOTS'):
            self.eval(cc, 'Theme.dark=true')
            QTest.qWait(220)
            target = Path(os.environ['GG_UI_REVIEW_SHOTS'])
            target.mkdir(parents=True, exist_ok=True)
            self.assertTrue(self.root.grabWindow().save(str(target / 'control-center.png')))

    def test_brightness_keyboard_and_expanded_display_controls(self):
        cc = self.desktop('shell/ControlCenter.qml', 'controlCenter')
        self.eval(cc, 'toggle()')
        self.root.requestActivate()
        level = self.find('ccBrightness')
        level.forceActiveFocus()
        QTest.keyClick(self.root, Qt.Key_Home)
        self.assertAlmostEqual(cc.property('brightness'), 0.02)
        QTest.keyClick(self.root, Qt.Key_End)
        self.assertEqual(cc.property('brightness'), 1.0)
        self.eval(cc, 'brightness=0.4')
        self.assertEqual(level.property('value'), 0.4)
        QTest.keyClick(self.root, Qt.Key_Return)
        self.assertEqual(cc.property('detail'), 'display')
        QTest.qWait(240)
        expanded = self.find('ccExpandedLevel')
        self.assertTrue(expanded.isVisible())
        self.assertEqual(expanded.property('value'), 0.4)
        QTest.keyClick(self.root, Qt.Key_Escape)
        self.assertEqual(cc.property('detail'), '')

    def test_connectivity_pill_keyboard_toggle_and_disclosure(self):
        cc = self.desktop('shell/ControlCenter.qml', 'controlCenter')
        self.eval(cc, 'toggle()')
        QTest.qWait(240)
        self.root.requestActivate()
        self.find('ccWifi').forceActiveFocus()
        self.assertTrue(cc.property('wifiOn'))
        QTest.keyClick(self.root, Qt.Key_Space)
        self.assertFalse(cc.property('wifiOn'))
        self.assertEqual(cc.property('detail'), '')
        QTest.keyClick(self.root, Qt.Key_Return)
        self.assertEqual(cc.property('detail'), 'wifi')

    def test_media_view_and_disabled_previous_without_a_player(self):
        cc = self.desktop('shell/ControlCenter.qml', 'controlCenter')
        self.eval(cc, 'open=true; showDetail("media")')
        QTest.qWait(240)
        self.assertEqual(cc.property('detail'), 'media')
        self.assertTrue(self.find('ccMediaDetail').isVisible())
        self.assertFalse(self.find('ccTransport:expanded:backward').isEnabled())
        self.assertFalse(self.find('ccTransport:expanded:forward').isEnabled())
        self.assertFalse(self.find('ccDetailSettings').isVisible())
        self.eval(cc, 'showDetail("not-a-module")')
        self.assertEqual(cc.property('detail'), 'media', 'unknown requests never open an empty page')

    def test_short_display_scrolls_extras_and_close_disables_input(self):
        cc = self.desktop('shell/ControlCenter.qml', 'controlCenter', height=600)
        self.eval(cc, 'open=true; editing=true')
        QTest.qWait(300)
        viewport = self.find('ccViewport')
        self.assertGreater(viewport.property('contentHeight'), viewport.property('height'))
        self.assertTrue(viewport.property('interactive'))
        self.eval(viewport, 'contentY=contentHeight-height')
        footer = self.find('ccEditControls')
        y = self.eval(footer, 'mapToItem(null,0,0).y')
        self.assertGreaterEqual(y, 30)
        self.assertLess(y + footer.property('height'), 600)
        self.eval(cc, 'open=false')
        self.assertFalse(self.find('ccMainControls').isEnabled())
        self.eval(cc, 'open=true; showDetail("display"); open=false; open=true')
        QTest.qWait(250)
        self.assertEqual(cc.property('detail'), 'display', 'an old close timer cannot reset a reopened detail')

    def test_launchpad_reference_grid_search_and_live_shell_chrome(self):
        apps = self.desktop('tests/fixtures/launch-surfaces.qml', 'launchpad', width=1536, height=998)
        self.eval(apps, 'present()')
        QTest.qWait(300)
        self.assertEqual(apps.property('columns'), 8)
        self.assertEqual(apps.property('rows'), 5)
        search = self.find('launchpadSearch')
        self.assertEqual(search.property('radius'), search.property('height') / 2)
        menu = self.find('globalMenuBar')
        self.assertGreater(menu.property('__layer'), apps.property('__layer'), 'the live menu bar stays over Launchpad')
        dock = self.find('launchpadDock')
        self.assertGreater(dock.property('__layer'), apps.property('__layer'), 'the live Dock stays over Launchpad')
        self.assertGreater(apps.property('bottomClearance'), dock.property('baseSize') + 22)
        self.eval(dock, 'openEntry({id:"no-such-test-app",startupClass:"no-such-test-app",synthetic:true})')
        self.assertFalse(apps.property('open'), 'opening a Dock destination also dismisses Launchpad')
        QTest.qWait(300)
        self.assertGreater(menu.property('__layer'), apps.property('__layer'))
        self.assertGreater(dock.property('__layer'), apps.property('__layer'))

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
        self.eval(apps, 'customIcons={}; userApps={}; scanned=false')
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
        self.assertFalse(apps.property('visible'))

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


if __name__ == '__main__':
    unittest.main(verbosity=2)
