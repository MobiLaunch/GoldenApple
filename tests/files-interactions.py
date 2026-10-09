#!/usr/bin/env python3
"""Files' real QML: selection, shortcuts, transfer feedback and remembered views.

Only read-only listings use the temporary filesystem. Clipboard, transfer and
preference writes are fixtures; backend effects are tested by files-workflow.py.
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
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/preview"))
import preview
APP = QGuiApplication([])


class System(preview.Preview):
    def __init__(self, home):
        super().__init__({"HOME":str(home), "USER":"preview", "XDG_CONFIG_HOME":str(home/"config"),
                          "XDG_DATA_HOME":str(home/"data"), "GG_FILES_PATH":str(home)},str(ROOT/"apps"),"'default'")
        self.commands=[]
        self.clipboard_paths=[]
        self.undo_response={"ok":True}
    @Slot("QVariant", result="QVariantMap")
    def run(self, cmd):
        cmd=cmd.toVariant() if hasattr(cmd,"toVariant") else cmd
        self.commands.append(cmd)
        if any(str(c).endswith("files/operations.py") for c in cmd):
            return dict(stdout='',stderr='',code=0,hang=True)
        if any(str(c).endswith("files/helper.py") for c in cmd) and cmd[2] != "list":
            if cmd[2]=="prefs-load": r=dict(ok=True,preferences={"folders":{}})
            elif cmd[2]=="clipboard-read": r=dict(ok=True,mode="move",paths=self.clipboard_paths)
            elif cmd[2]=="info": r=dict(ok=True,info={"name":"Note","path":cmd[3],"permissions":"-rw-r--r--","mime":"text/plain","size":10,"modified":1})
            elif cmd[2]=="undo": r=self.undo_response
            else: r=dict(ok=True)
            return dict(stdout=json.dumps(r),stderr='',code=0)
        return super().run(cmd)


class Interactions(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.home=Path(self.tmp.name)
        for name in ("a.txt","b.txt","c.txt","d.txt"): (self.home/name).write_text(name)
        (self.home/"Downloads").mkdir()
        self.system=System(self.home)
        self.engine=QQmlEngine()
        self.engine.addImportPath(str(ROOT/"tools/preview/qml"))
        self.engine.rootContext().setContextProperty("__preview",self.system)
        self.component=QQmlComponent(self.engine,QUrl.fromLocalFile(str(ROOT/"tools/preview/Desktop.qml")))
        self.assertEqual(self.component.status(),QQmlComponent.Ready)
        self.root=self.component.createWithInitialProperties({"targetUrl":QUrl.fromLocalFile(str(ROOT/"apps/files.qml"))})
        self.assertIsNotNone(self.root)
        self.root.requestActivate(); QTest.qWait(180)
        self.files=self.root.findChild(QObject,"filesApp")
        self.assertIsNotNone(self.files)
        self.assertTrue(self.files.property("prefsReady"))
        self.eval('forceActiveFocus()')

    def eval(self, code):
        e=QQmlExpression(QQmlEngine.contextForObject(self.files),self.files,code)
        v=e.evaluate()[0]
        self.assertFalse(e.hasError(),e.error().toString())
        return v.toVariant() if hasattr(v,"toVariant") else v

    def tearDown(self):
        self.root.deleteLater(); self.engine.deleteLater()
        APP.processEvents(); APP.sendPostedEvents(None,QEvent.DeferredDelete)
        self.tmp.cleanup()

    def test_sidebar_choreography_keeps_content_and_glass_in_sync(self):
        # This is the real Files QML, using the AppWindow implementation.
        self.assertAlmostEqual(self.eval('win.presentedSidebarWidth'),210,delta=1)
        self.assertAlmostEqual(self.eval('win.contentX'),210,delta=1)
        self.eval('win.sidebarShown=false')
        QTest.qWait(250)
        self.assertAlmostEqual(self.eval('win.presentedSidebarWidth'),0,delta=2)
        self.assertAlmostEqual(self.eval('win.contentX'),0,delta=2)
        self.eval('win.sidebarShown=true')
        QTest.qWait(250)
        self.assertAlmostEqual(self.eval('win.presentedSidebarWidth'),210,delta=2)
        self.assertAlmostEqual(self.eval('win.contentX'),210,delta=2)
        # Reduced motion snaps both edges immediately, with no orphan panel.
        self.eval('Theme.reduceMotion=true; win.sidebarShown=false')
        APP.processEvents()
        self.assertAlmostEqual(self.eval('win.presentedSidebarWidth'),0,delta=1)
        self.assertAlmostEqual(self.eval('win.contentX'),0,delta=1)
        self.eval('win.sidebarShown=true')
        APP.processEvents()
        self.assertAlmostEqual(self.eval('win.presentedSidebarWidth'),210,delta=1)
        self.assertAlmostEqual(self.eval('win.contentWidth'),self.eval('win.width')-210,delta=1)

    def test_files_rename_and_empty_trash_use_shared_document_sheets(self):
        self.eval('files.dialogMode="mkdir"; files.dialogText="New Folder"; editDialog.open()')
        self.assertTrue(self.eval('editDialog.shown'))
        self.assertIsNotNone(self.root.findChild(QObject,'filesEditSheet'))
        self.eval('editDialog.close()')
        self.assertFalse(self.eval('editDialog.shown'))
        self.eval('confirmEmpty.open()')
        self.assertTrue(self.eval('confirmEmpty.shown'))
        self.assertIsNotNone(self.root.findChild(QObject,'filesEmptyTrashSheet'))
        self.eval('confirmEmpty.close()')
        self.assertFalse(self.eval('confirmEmpty.shown'))

    def test_quick_look_morph_and_nonblocking_exit(self):
        self.eval('select(entries[0]); quickLook.open=true')
        card=self.root.findChild(QObject,'quickLookCard')
        surface=self.root.findChild(QObject,'quickLookHitArea')
        self.assertIsNotNone(card)
        self.assertIsNotNone(surface)
        self.assertTrue(surface.property('enabled'))
        self.assertTrue(self.eval('quickLook.visible'))
        QTest.qWait(260)
        self.assertAlmostEqual(card.property('scale'),1.0,delta=0.03)
        self.eval('quickLook.open=false')
        self.assertFalse(surface.property('enabled'),
                         'Quick Look must release mouse input before its exit fade completes')
        self.assertFalse(card.property('enabled'),
                         'Quick Look close and Open controls must also be inert during exit')
        QTest.qWait(230)
        self.assertFalse(self.eval('quickLook.visible'))

    def test_quick_look_reduce_motion_avoids_pop_and_preview_remains_navigable(self):
        self.eval('Theme.reduceMotion=true; select(entries[0]); quickLook.open=true')
        card=self.root.findChild(QObject,'quickLookCard')
        self.assertAlmostEqual(card.property('scale'),1.0,delta=0.01)
        # Selection can change while Quick Look stays open. The preview retargets
        # its entry without opening a new surface and without a size tween.
        self.eval('select(entries[1])')
        APP.processEvents()
        self.assertEqual(self.eval('quickLook.entry.path'),self.eval('entries[1].path'))
        self.assertTrue(self.eval('quickLook.open'))
        self.eval('quickLook.open=false')
        APP.processEvents()
        self.assertFalse(self.eval('quickLook.visible'))

    def test_finder_grid_list_crossfade_leaves_only_active_view_interactive(self):
        self.eval('select(entries[1])')
        selected=self.eval('selectedPath')
        grid=self.root.findChild(QObject,"filesGridView")
        listing=self.root.findChild(QObject,"filesListView")
        self.assertIsNotNone(grid)
        self.assertIsNotNone(listing)
        self.eval('Theme.reduceMotion=false; view="grid"')
        QTest.qWait(155)
        self.assertTrue(grid.property("enabled"))
        self.assertFalse(listing.property("enabled"))
        self.eval('switchView("list")')
        # The outgoing view can remain painted briefly; it must immediately
        # relinquish input, drag targets and scrollbar ownership.
        self.assertFalse(grid.property("enabled"))
        self.assertTrue(listing.property("enabled"))
        QTest.qWait(170)
        self.assertFalse(grid.property("visible"))
        self.assertTrue(listing.property("visible"))
        self.assertAlmostEqual(listing.property("opacity"),1.0,delta=0.03)
        self.eval('Theme.reduceMotion=true; switchView("grid")')
        APP.processEvents()
        self.assertFalse(listing.property("visible"))
        self.assertAlmostEqual(grid.property("opacity"),1.0,delta=0.03)
        self.assertTrue(grid.property("enabled"))
        self.assertEqual(self.eval('selectedPath'), selected,
                         'switching layout must not change file selection')

    def test_grid_marquee_selects_intersecting_icons_and_modifier_combinations(self):
        self.eval('view="grid"; grid.forceLayout()')
        APP.processEvents()
        bg=self.root.findChild(QObject,"filesMarqueeBackground")
        self.assertIsNotNone(bg)
        self.assertTrue(bg.property("enabled"))
        result=self.eval('''(() => {
            const a = grid.itemAtIndex(0)
            const b = grid.itemAtIndex(1)
            if (!a || !b) return false
            const p0 = a.mapToItem(grid, 0, 0)
            const p1 = b.mapToItem(grid, 0, 0)
            marqueeBackground.startX = p0.x + 4
            marqueeBackground.startY = p0.y + 4
            marqueeBackground.originalPaths = []
            marqueeBackground.modifiers = 0
            marqueeBackground.applyRectangle(p1.x + b.width - 4, p1.y + b.height - 4)
            return true
        })()''')
        self.assertTrue(result, "grid cells should be instantiated for selection")
        self.assertEqual(self.eval('selectedPaths.length'),2)
        self.assertEqual(self.eval('selectedPaths[0]'),self.eval('entries[0].path'))
        # Control removes selected hits; Shift adds without losing the old set.
        self.eval('marqueeBackground.originalPaths = [entries[0].path]; marqueeBackground.modifiers = Qt.ControlModifier')
        self.eval('marqueeBackground.applyRectangle(marqueeBackground.lastX, marqueeBackground.lastY)')
        self.assertEqual(self.eval('selectedPaths.length'),1)
        self.assertEqual(self.eval('selectedPaths[0]'),self.eval('entries[1].path'))
        self.eval('marqueeBackground.modifiers = Qt.ShiftModifier')
        self.eval('marqueeBackground.applyRectangle(marqueeBackground.lastX, marqueeBackground.lastY)')
        self.assertEqual(self.eval('selectedPaths.length'),2)
        self.assertEqual(self.eval('query'),"", "marquee must not filter the directory")

    def test_marquee_is_disabled_for_hidden_grid_or_active_operations(self):
        bg=self.root.findChild(QObject,"filesMarqueeBackground")
        self.eval('view="grid"')
        APP.processEvents()
        self.assertTrue(bg.property('enabled'))
        self.eval('view="list"')
        APP.processEvents()
        self.assertFalse(bg.property('enabled'))
        self.eval('view="grid"; loading=true')
        APP.processEvents()
        self.assertFalse(bg.property('enabled'))

    def test_type_to_select_matches_prefix_without_filtering_directory(self):
        count=self.eval('entries.length')
        self.assertTrue(self.eval('typeSelect("a")'))
        self.assertEqual(self.eval('selectedEntry.name'),"a.txt")
        self.assertEqual(self.eval('typeAhead'),"a")
        QTest.qWait(165)  # allow the 120 ms opacity transition to paint
        cue=self.root.findChild(QObject,"filesTypeAheadCue")
        self.assertIsNotNone(cue)
        self.assertTrue(cue.property('visible'))
        # A nonmatching prefix falls back to the new character and wraps.
        self.assertTrue(self.eval('typeSelect("b")'))
        self.assertEqual(self.eval('selectedEntry.name'),"b.txt")
        self.assertEqual(self.eval('typeAhead'),"b")
        self.assertEqual(self.eval('entries.length'),count)
        self.assertEqual(self.eval('query'),"")
        self.assertTrue(self.eval('typeSelect("b")'))
        self.assertEqual(self.eval('selectedEntry.name'),"b.txt")
        QTest.qWait(1080)
        self.assertEqual(self.eval('typeAhead'),"")
        self.assertFalse(cue.property('visible'))

    def test_type_to_select_ignores_open_dialogs_and_quick_look(self):
        self.eval('editDialog.open()')
        self.assertFalse(self.eval('typeSelect("a")'))
        self.eval('editDialog.close()')
        self.eval('select(entries[0]); quickLook.open=true')
        self.assertFalse(self.eval('typeSelect("a")'))
        self.eval('quickLook.open=false')
        self.assertTrue(self.eval('typeSelect("a")'))
        # Switching directories clears any half-entered prefix.
        self.eval('navigate(home + "/Downloads")')
        self.assertEqual(self.eval('typeAhead'),"")

    def test_keyboard_home_end_page_and_shift_range(self):
        self.eval('forceActiveFocus()')
        QTest.keyClick(self.root,Qt.Key_End)
        self.assertEqual(self.eval('selectedPath'),self.eval('entries[entries.length - 1].path'))
        QTest.keyClick(self.root,Qt.Key_Home,Qt.ShiftModifier)
        self.assertEqual(self.eval('selectedPaths.length'),self.eval('entries.length'))
        QTest.keyClick(self.root,Qt.Key_PageDown)
        self.assertTrue(self.eval('selectedIndex >= 0'))
        QTest.keyClick(self.root,Qt.Key_PageUp)
        self.assertTrue(self.eval('selectedIndex >= 0'))

    def test_range_toggle_all_and_clear_on_navigation(self):
        self.eval('view="list"; select(entries[0])')
        QTest.keyClick(self.root,Qt.Key_Down,Qt.ShiftModifier)
        self.assertEqual(self.eval('selectedPaths.length'),2)
        self.eval('select(entries[3], Qt.ControlModifier)')
        self.assertEqual(self.eval('selectedPaths.length'),3)
        QTest.keyClick(self.root,Qt.Key_A,Qt.ControlModifier)
        self.assertEqual(self.eval('selectedPaths.length'),self.eval('entries.length'))
        QTest.keyClick(self.root,Qt.Key_Escape)
        self.assertEqual(self.eval('selectedPaths.length'),0)
        self.eval('selectAll()')
        self.eval('navigate(home + "/Downloads")')
        self.assertEqual(self.eval('selectedPaths.length'),0)

    def test_cut_paste_shortcuts_and_busy_feedback(self):
        self.eval('select(entries.find(e => e.name === "a.txt"))')
        QTest.keyClick(self.root,Qt.Key_X,Qt.ControlModifier)
        QTest.qWait(30)
        self.assertEqual(self.eval('cutPaths'),[str(self.home/"a.txt")])
        self.system.clipboard_paths=[str(self.home/"a.txt")]
        self.eval('navigate(home + "/Downloads")'); QTest.qWait(30)
        self.eval('forceActiveFocus()')
        QTest.keyClick(self.root,Qt.Key_V,Qt.ControlModifier)
        QTest.qWait(30)
        self.assertTrue(self.files.property("busy"))
        self.assertEqual(self.eval('transferRequest.mode'),"move")
        self.assertEqual(self.eval('transferRequest.paths'),self.system.clipboard_paths)
        self.eval('startTransfer([home + "/b.txt"], path, "copy")')
        self.assertIn("already running",self.files.property("notice"))
        self.eval('requestClose()')
        self.assertIn("before closing",self.files.property("notice"))

    def test_conflict_keyboard_cancel_and_finished_summary(self):
        self.eval('startTransfer([home+"/a.txt"],home+"/Downloads","copy")')
        QTest.qWait(20)
        self.eval('takeTransfer(JSON.stringify({event:"conflict",name:"a.txt"}))')
        QTest.qWait(10)
        keep=self.root.findChild(QObject,"filesKeepBoth")
        self.assertEqual(self.root.activeFocusItem(),keep)
        QTest.keyClick(self.root,Qt.Key_Escape)
        self.assertTrue(self.files.property("cancelRequested"))
        self.assertIsNone(self.eval('conflict'))
        self.eval('takeTransfer(JSON.stringify({event:"finished",ok:true,cancelled:true,completed:[{path:home+"/Downloads/a.txt",source:home+"/a.txt",action:"copy"}],skipped:[],errors:[],destination:home+"/Downloads"}))')
        self.assertTrue(self.root.findChild(QObject,"filesTransferPanel").property("visible"))
        self.assertEqual(self.eval('transferResult.completed.length'),1)
        self.assertTrue(self.eval('transferResult.cancelled'))

    def test_sort_and_per_folder_view_restore(self):
        self.eval('view="list"; sortKey="name"; descending=true')
        self.assertEqual(self.eval('entries.filter(e => !e.folder).map(e=>e.name)'),["d.txt","c.txt","b.txt","a.txt"])
        self.eval('navigate(home+"/Downloads")')
        self.assertEqual(self.files.property("view"),"grid")
        self.eval('navigate(home)')
        self.assertEqual(self.files.property("view"),"list")
        self.assertTrue(self.files.property("descending"))
        self.assertEqual(self.eval('preferences.folders[home].view'),"list")

    def test_get_info_shortcut(self):
        self.eval('select(entries.find(e => e.name === "a.txt"))')
        QTest.keyClick(self.root,Qt.Key_I,Qt.ControlModifier)
        QTest.qWait(30)
        self.assertTrue(self.root.findChild(QObject,"filesInfo").property("visible"))
        self.assertEqual(self.eval('info.path'),str(self.home/"a.txt"))
        self.assertTrue(self.eval('infoDialog.shown'))
        self.assertIsNotNone(self.root.findChild(QObject,'sharedSheetPanel'))
        self.eval('infoDialog.close()')
        self.assertFalse(self.eval('infoDialog.shown'))
        self.assertTrue(self.files.hasActiveFocus())

    def test_undo_shortcut_updates_creation_identity_after_rename(self):
        path=str(self.home/"Folder")
        self.eval('undoStack=[{kind:"mkdir",path:'+json.dumps(path)+',identity:[1,2],created:10},{kind:"rename",path:'+json.dumps(path+'2')+',original:'+json.dumps(path)+',identity:[1,2]}]')
        self.system.undo_response=dict(ok=True,path=path,identity=[1,2],created=20)
        QTest.keyClick(self.root,Qt.Key_Z,Qt.ControlModifier)
        QTest.qWait(30)
        self.assertEqual(self.eval('undoStack.length'),1)
        self.assertEqual(self.eval('undoStack[0].created'),20)

    def test_small_window_large_text_keeps_sidebar_and_dialogs_reachable(self):
        self.eval('win.width=720; win.height=440; Theme.textScale=1.5')
        QTest.qWait(30)
        sidebar=self.root.findChild(QObject,"filesSidebarScroll")
        self.assertTrue(sidebar.property("clip"))
        self.assertGreater(sidebar.property("contentHeight"),sidebar.property("height"))
        self.eval('info={name:"Long file name",location:"/" + "very-long-path/".repeat(80),mime:"text/plain",size:1,modified:1,permissions:"-rw-r--r--"}; infoDialog.open()')
        self.assertLess(self.eval('infoDialog.panel.height'),self.eval('win.height'))
        self.assertGreater(self.eval('infoScroll.height'),0)
        self.eval('infoDialog.close(); Theme.textScale=1')


if __name__=="__main__":
    unittest.main(verbosity=2)
