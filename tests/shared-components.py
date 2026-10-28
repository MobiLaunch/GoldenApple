#!/usr/bin/env python3
"""The shared components T-2.9 adds to apps/lib, each in a scene of its own,
driven with real key and pointer events: how each is read out (its
accessible role and name), how it's used from the keyboard, and what it
does with Reduce Motion on.

Spinner, Badge, Tooltip, InlineBanner, Toast, Alert, ConfirmSheet, Popover,
SearchField, ListRow, FormRow, FormSection, NavigationSplitView."""
import os
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
from pathlib import Path
import time
import unittest

from PySide6.QtCore import QEvent, QObject, QPoint, QPointF, Qt, QUrl
from PySide6.QtGui import QAccessible, QGuiApplication, QKeySequence
from PySide6.QtQml import QQmlEngine, QQmlExpression
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[1]
APP = QGuiApplication.instance() or QGuiApplication([])
HEAD = 'import QtQuick\nimport "../apps/lib"\nimport "../apps/lib/theme"\n'


class Scene(unittest.TestCase):
    def scene(self, body, width=640, height=480, reduce_motion=False):
        self.view = QQuickView()
        self.view.engine().addImportPath(str(ROOT / "tools/preview/qml"))
        self.view.setResizeMode(QQuickView.ResizeMode.SizeRootObjectToView)
        self.view.resize(width, height)
        # setData isn't on QQuickView; a file next to the tests resolves "../apps/lib".
        path = ROOT / "tests" / f".scene-{self.id().split('.')[-1]}.qml"
        path.write_text(HEAD + "Rectangle {\n    id: root\n    color: Theme.windowBg\n" + body + "\n}\n")
        self.addCleanup(lambda: path.unlink(missing_ok=True))
        self.view.setSource(QUrl.fromLocalFile(str(path)))
        self.assertEqual(self.view.status(), QQuickView.Status.Ready, [e.toString() for e in self.view.errors()])
        self.view.show()
        self.addCleanup(self.view.deleteLater)
        self.root = self.view.rootObject()
        self.js(f"Theme.reduceMotion = {'true' if reduce_motion else 'false'}")
        QTest.qWait(30)
        return self.root

    def js(self, code):
        e = QQmlExpression(QQmlEngine.contextForObject(self.root), self.root, code)
        v = e.evaluate()[0]
        self.assertFalse(e.hasError(), e.error().toString())
        return v.toVariant() if hasattr(v, "toVariant") else v

    def item(self, name):
        found = self.root.findChild(QObject, name)
        if found is None:                        # visual children (Repeater delegates) aren't QObject children
            stack = [self.root]
            while stack:
                it = stack.pop()
                if it.objectName() == name:
                    return it
                stack.extend(it.childItems())
        self.assertIsNotNone(found, name)
        return found

    def wait(self, expression, timeout=3):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if self.js(expression):
                return
            QTest.qWait(15)
        self.fail(f"timed out waiting for {expression}")

    def input_of(self, name):
        """A TextField's own text input (PySide can't hand it over by property)."""
        stack = [self.item(name)]
        while stack:
            it = stack.pop()
            if it.objectName() == "textFieldNativeInput":
                return it
            stack.extend(it.childItems())
        self.fail(f"{name} has no text input")

    def type(self, text):
        for c in text:
            QTest.keyClick(self.view, Qt.Key(ord(c.upper())), Qt.KeyboardModifier.NoModifier)
        QTest.qWait(20)

    def key(self, key, modifiers=Qt.KeyboardModifier.NoModifier):
        QTest.keyClick(self.view, key, modifiers)
        QTest.qWait(20)

    def accessible(self, obj):
        iface = QAccessible.queryAccessibleInterface(obj)
        self.assertIsNotNone(iface, obj)
        return iface.role(), iface.text(QAccessible.Text.Name)

    def center(self, name):
        it = self.item(name)
        p = it.mapToScene(QPointF(it.width() / 2, it.height() / 2))
        return QPoint(int(p.x()), int(p.y()))


class Indicators(Scene):
    def test_spinner_turns_or_breathes(self):
        self.scene('Spinner { objectName: "spin"; label: "Loading messages" }')
        self.assertEqual(self.accessible(self.item("spin")), (QAccessible.Role.ProgressBar, "Loading messages"))
        first = self.js("children[0].lead")
        QTest.qWait(300)
        self.assertNotEqual(self.js("children[0].lead"), first, "the bright spoke goes round")
        self.js("Theme.reduceMotion = true")
        held = self.js("children[0].lead")
        QTest.qWait(700)
        self.assertEqual(self.js("children[0].lead"), held, "Reduce Motion: the spokes stay put")
        self.assertLess(self.js("children[0].opacity"), 1, "and it breathes instead")
        self.js("children[0].running = false")
        self.assertFalse(self.js("children[0].visible"))

    def test_badge(self):
        self.scene('Badge { objectName: "badge"; count: 0; label: "unread" }')
        self.assertFalse(self.js("children[0].visible"), "zero hides it")
        self.js("children[0].count = 3")
        self.wait("children[0].visible && children[0].scale > 0.95")
        self.assertEqual(self.accessible(self.item("badge"))[1], "3 unread")
        self.js("children[0].count = 4")
        QTest.qWait(40)
        self.assertGreater(self.js("children[0].bump"), 1, "a new one bumps it")
        self.js("children[0].count = 150")
        self.assertEqual(self.js("children[0].shownText"), "99+")
        self.js("Theme.reduceMotion = true; children[0].count = 0")
        self.assertFalse(self.js("children[0].visible"), "Reduce Motion: gone at once")
        self.js("children[0].count = 2")
        self.assertEqual(self.js("children[0].scale"), 1, "and back at once, no spring")


class Help(Scene):
    def test_tooltip_after_a_rest_or_on_focus(self):
        self.scene('''
    Rectangle {
        objectName: "target"; x: 200; y: 200; width: 80; height: 30; color: "gray"
        activeFocusOnTab: true
        Accessible.role: Accessible.Button; Accessible.name: "Trash"
        Tooltip { objectName: "tip"; text: "Move to Trash"; delay: 200 }
    }''')
        target = self.item("target")
        self.assertEqual(QAccessible.queryAccessibleInterface(target).text(QAccessible.Text.Description), "Move to Trash",
                         "its parent is described by it")
        QTest.mouseMove(self.view, self.center("target"))
        QTest.qWait(100)
        self.assertFalse(self.item("tip").property("shown"), "not before the pointer rests")
        QTest.qWait(400)
        self.assertTrue(self.item("tip").property("shown"))
        bubble = self.item("tooltipBubble")
        self.assertLess(bubble.mapToScene(QPointF(0, 0)).y(), 200, "above its parent, with room there")
        self.assertEqual(self.accessible(bubble), (QAccessible.Role.ToolTip, "Move to Trash"))
        QTest.mouseMove(self.view, QPoint(10, 10))
        self.wait("!children[0].children[0].shown")
        target.forceActiveFocus()
        self.wait("children[0].children[0].shown")

    def test_inline_banner(self):
        self.scene('''
    property int dismissals: 0
    property int actions: 0
    InlineBanner { objectName: "banner"; width: 400; kind: "error"; text: ""; actionText: "Try Again"
                   onDismissed: root.dismissals++; onAction: root.actions++ }''', reduce_motion=True)
        self.assertFalse(self.js("children[0].visible"))
        self.js('children[0].text = "Your change couldn\'t be saved."')
        self.assertGreater(self.js("children[0].height"), 30, "Reduce Motion: open at once")
        box = self.item("inlineBannerBox")
        self.assertEqual(self.accessible(box), (QAccessible.Role.AlertMessage, "Your change couldn't be saved."))
        self.key(Qt.Key.Key_Tab)                  # Try Again
        self.key(Qt.Key.Key_Space)
        self.assertEqual(self.js("actions"), 1)
        self.key(Qt.Key.Key_Tab)                  # Dismiss
        self.key(Qt.Key.Key_Return)
        self.assertEqual(self.js("dismissals"), 1)
        self.assertFalse(self.js("children[0].visible"))
        self.js('children[0].text = ""; children[0].text = "Still couldn\'t be saved."')
        self.assertTrue(self.js("children[0].visible"), "the next message shows again")

    def test_toast_queue_and_action(self):
        self.scene('''
    property int retried: 0
    Toast { id: toast; objectName: "toasts"; anchors.fill: parent }''')
        self.js('toast.show("Link copied", { timeout: 250 })')
        self.js('toast.show("Couldn\'t save", { kind: "error", actionText: "Try Again", action: () => root.retried++ })')
        pill = self.item("toast")
        self.wait("toast.current && toast.current.text === 'Link copied'")
        self.assertEqual(self.accessible(pill), (QAccessible.Role.AlertMessage, "Link copied"))
        self.wait("toast.current && toast.current.text === \"Couldn't save\"", timeout=3)
        QTest.qWait(450)
        button = [c for c in pill.findChildren(QObject) if c.property("text") == "Try Again"][0]
        QTest.mouseClick(self.view, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier,
                         button.mapToScene(QPointF(button.width() / 2, button.height() / 2)).toPoint())
        self.assertEqual(self.js("retried"), 1)
        self.wait("!toast.showing")
        self.assertFalse(pill.hasActiveFocus(), "it never takes focus from the work")


ALERT = '''
    property var picked: []
    Rectangle { id: opener; objectName: "opener"; width: 80; height: 30; activeFocusOnTab: true }
    Alert {
        id: alert
        title: "Delete “Ferry tickets”?"; message: "This can't be undone."
        buttons: %s
        onChosen: (role, index) => root.picked = root.picked.concat([role])
    }'''


class Modal(Scene):
    def open(self):
        self.item("opener").forceActiveFocus()
        self.js("alert.open()")
        QTest.qWait(300)

    def test_alert_order_and_keys(self):
        self.scene(ALERT % '[{ text: "Save", role: "default" }, { text: "Cancel", role: "cancel" }, { text: "Don\'t Save", role: "other" }]')
        self.open()
        xs = {r: self.item("alertButton-" + r).mapToScene(QPointF(0, 0)).x() for r in ("default", "cancel", "other")}
        self.assertTrue(xs["default"] > xs["cancel"] > xs["other"], f"right to left: default, cancel, others {xs}")
        self.assertTrue(self.item("alertButton-default").property("prominent"))
        self.key(Qt.Key.Key_Return)
        self.assertEqual(self.js("picked"), ["default"])
        self.assertTrue(self.item("opener").hasActiveFocus(), "focus goes back to what opened it")
        self.open()
        self.key(Qt.Key.Key_Escape)
        self.assertEqual(self.js("picked"), ["default", "cancel"])

    def test_a_destructive_choice_is_never_the_default(self):
        self.scene(ALERT % '[{ text: "Delete", role: "destructive" }, { text: "Cancel", role: "cancel" }]')
        self.open()
        delete, cancel = self.item("alertButton-destructive"), self.item("alertButton-cancel")
        self.assertTrue(delete.property("destructive"))
        self.assertFalse(delete.property("prominent"))
        self.assertTrue(cancel.property("prominent"))
        self.key(Qt.Key.Key_Return)
        self.assertEqual(self.js("picked"), ["cancel"], "Return can't erase anything")
        self.open()
        QTest.mouseClick(self.view, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier, QPoint(5, 470))
        self.assertEqual(self.js("picked"), ["cancel", "cancel"], "clicking away is Cancel")
        self.open()
        delete = self.item("alertButton-destructive")
        QTest.mouseClick(self.view, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier,
                         delete.mapToScene(QPointF(delete.width() / 2, delete.height() / 2)).toPoint())
        self.assertEqual(self.js("picked"), ["cancel", "cancel", "destructive"])

    def test_alert_is_read_as_one(self):
        self.scene(ALERT % '[{ text: "OK", role: "default" }]')
        self.open()
        column = [c for c in self.root.findChildren(QObject) if c.property("spacing") == 10 and c.property("width")][0]
        role, name = self.accessible(column)
        self.assertEqual((role, name), (QAccessible.Role.AlertMessage, "Delete “Ferry tickets”?"))

    def test_confirm_sheet(self):
        self.scene('''
    property string said: ""
    Rectangle { id: opener; objectName: "opener"; width: 80; height: 30; activeFocusOnTab: true }
    ConfirmSheet { id: alert; title: "Empty the Trash?"; confirmText: "Empty Trash"; destructive: true
                   onConfirmed: root.said += "confirmed "; onCancelled: root.said += "cancelled " }''')
        self.open()
        self.key(Qt.Key.Key_Return)
        self.assertEqual(self.js("said"), "cancelled ")
        self.open()
        b = self.item("alertButton-destructive")
        QTest.mouseClick(self.view, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier,
                         b.mapToScene(QPointF(b.width() / 2, b.height() / 2)).toPoint())
        self.assertEqual(self.js("said"), "cancelled confirmed ")
        self.js("alert.destructive = false")
        self.open()
        self.key(Qt.Key.Key_Return)
        self.assertEqual(self.js("said"), "cancelled confirmed confirmed ", "not destructive: Return confirms")


class Popovers(Scene):
    BODY = '''
    Rectangle { id: anchor; objectName: "anchor"; x: 200; y: 60; width: 60; height: 24; activeFocusOnTab: true
                Accessible.name: "Event" }
    Popover {
        id: pop; anchorItem: anchor; panelWidth: 240
        Column {
            spacing: 8
            TextField { objectName: "first"; width: 200; placeholder: "Title" }
            TextField { objectName: "second"; width: 200; placeholder: "Place" }
        }
    }'''

    def test_open_tab_trap_and_close(self):
        self.scene(self.BODY)
        self.item("anchor").forceActiveFocus()
        self.js("pop.open()")
        QTest.qWait(300)
        panel = self.item("popoverPanel")
        self.assertGreater(panel.mapToScene(QPointF(0, 0)).y(), 84, "below its anchor")
        self.assertEqual(self.accessible(panel)[0], QAccessible.Role.Dialog)
        first, second = self.input_of("first"), self.input_of("second")
        self.assertTrue(first.hasActiveFocus(), "focus goes in")
        self.key(Qt.Key.Key_Tab)
        self.assertTrue(second.hasActiveFocus())
        self.key(Qt.Key.Key_Tab)
        self.assertTrue(first.hasActiveFocus(), "Tab goes round, not out")
        self.key(Qt.Key.Key_Backtab)
        self.assertTrue(second.hasActiveFocus(), "and back round")
        self.key(Qt.Key.Key_Escape)
        self.assertFalse(self.js("pop.shown"))
        self.assertTrue(self.item("anchor").hasActiveFocus(), "focus goes back to its anchor")

    def test_click_away_and_reduce_motion(self):
        self.scene(self.BODY, reduce_motion=True)
        self.js("pop.open()")
        QTest.qWait(20)
        self.assertEqual(self.item("popoverPanel").property("scale"), 1, "Reduce Motion: no growing")
        QTest.mouseClick(self.view, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier, QPoint(600, 450))
        self.assertFalse(self.js("pop.shown"))

    def test_above_when_theres_no_room_below(self):
        self.scene(self.BODY.replace("y: 60", "y: 440"))
        self.js("pop.open()")
        QTest.qWait(300)
        self.assertLess(self.item("popoverPanel").mapToScene(QPointF(0, 0)).y(), 440)


class Search(Scene):
    def test_search_field(self):
        self.scene('''
    property var heard: []
    property int cancels: 0
    Rectangle { objectName: "elsewhere"; width: 50; height: 20; activeFocusOnTab: true; focus: true }
    SearchField { id: find; objectName: "find"; y: 40; width: 240; delay: 60
                  onSearched: (t) => root.heard = root.heard.concat([t]); onCancelled: root.cancels++ }''')
        input = self.input_of("find")
        self.assertTrue(QAccessible.queryAccessibleInterface(input).state().searchEdit, "read out as a search field")
        self.key(Qt.Key.Key_F, Qt.KeyboardModifier.ControlModifier)
        self.assertTrue(input.hasActiveFocus(), "⌘F puts the cursor in it")
        self.type("ferry")
        self.wait("heard.length === 1")
        self.assertEqual(self.js("heard"), ["ferry"], "once the typing pauses, not per letter")
        self.key(Qt.Key.Key_Return)
        self.assertEqual(self.js("find.recents"), ["ferry"])
        self.key(Qt.Key.Key_Escape)
        self.assertEqual(self.js("find.text"), "")
        self.assertEqual(self.js("heard[heard.length - 1]"), "")
        self.assertTrue(input.hasActiveFocus(), "the first Escape only clears")
        self.key(Qt.Key.Key_Down)
        QTest.qWait(200)
        menus = []
        stack = [self.view.contentItem()]             # it opens on the window, over everything
        while stack:
            it = stack.pop()
            if it.property("menuWidth") is not None and it.property("visible"):
                menus.append(it)
            stack.extend(it.childItems())
        self.assertEqual(len(menus), 1, "↓ in an empty field offers the recent searches")
        self.assertIn("ferry", [i.get("text") for i in menus[0].property("items").toVariant()])
        self.key(Qt.Key.Key_Escape)                   # closes the menu
        QTest.qWait(300)
        input.forceActiveFocus()
        self.key(Qt.Key.Key_Escape)
        self.assertFalse(input.hasActiveFocus(), "an Escape in an empty field lets go")
        self.assertGreaterEqual(self.js("cancels"), 1)


class Rows(Scene):
    def test_list_rows(self):
        self.scene('''
    property int opened: 0
    FormSection {
        id: section; objectName: "section"; width: 400; title: "Network"; footer: "Shown in the menu bar."
        ListRow { objectName: "wifi"; title: "Wi-Fi"; subtitle: "Home"; symbol: "wifi"; chevron: true; onClicked: root.opened++ }
        ListRow { objectName: "plain"; title: "Address"; Text { text: "10.0.0.2" } }
        ListRow { objectName: "pick"; title: "Automatic"; selectable: true; selected: true }
        FormRow { objectName: "battery"; title: "Show percentage"; Switch { objectName: "toggle" } }
    }''')
        self.assertEqual(self.accessible(self.item("section")), (QAccessible.Role.Grouping, "Network"))
        self.assertEqual(self.accessible(self.item("wifi")), (QAccessible.Role.Button, "Wi-Fi"))
        self.assertEqual(self.accessible(self.item("pick"))[0], QAccessible.Role.ListItem)
        self.assertTrue(QAccessible.queryAccessibleInterface(self.item("pick")).state().selected)
        self.assertEqual(self.accessible(self.item("toggle"))[1], "Show percentage", "a form's control is named by its row")
        self.key(Qt.Key.Key_Tab)
        self.assertTrue(self.item("wifi").hasActiveFocus())
        self.key(Qt.Key.Key_Space)
        self.key(Qt.Key.Key_Return)
        self.assertEqual(self.js("opened"), 2)
        self.key(Qt.Key.Key_Tab)
        self.assertFalse(self.item("plain").hasActiveFocus(), "a row that does nothing isn't a stop")
        self.assertTrue(self.item("pick").hasActiveFocus())
        self.assertGreater(self.js("section.height"), self.js("section.children[1].y + section.children[1].height"),
                           "the footer is under the card")
        self.assertFalse(self.item("wifi").property("first") is False, "the first row has no hairline")


class Split(Scene):
    BODY = '''
    NavigationSplitView {
        id: split; objectName: "split"; anchors.fill: parent; sidebarWidth: 200; minimumDetailWidth: 300
        sidebar: [ Rectangle { anchors.fill: parent; color: "lightgray"
                               ListRow { objectName: "mailbox"; title: "Inbox"; selectable: true } } ]
        Rectangle { anchors.fill: parent; color: "white" }
    }'''

    def test_wide_toggle_and_reduce_motion(self):
        self.scene(self.BODY, width=800, reduce_motion=True)
        sidebar, detail = self.item("splitSidebar"), self.item("splitDetail")
        self.assertEqual((sidebar.property("x"), detail.property("x")), (0, 200))
        self.assertEqual(self.accessible(sidebar)[0], QAccessible.Role.Pane)
        self.key(Qt.Key.Key_S, Qt.KeyboardModifier.ControlModifier | Qt.KeyboardModifier.MetaModifier)
        self.assertEqual((sidebar.property("x"), detail.property("x")), (-200, 0), "⌃⌘S hides it; at once with Reduce Motion")
        self.key(Qt.Key.Key_S, Qt.KeyboardModifier.ControlModifier | Qt.KeyboardModifier.MetaModifier)
        self.assertEqual(detail.property("x"), 200)

    def test_narrow_it_slides_over(self):
        self.scene(self.BODY, width=800)
        self.view.resize(420, 480)
        QTest.qWait(600)
        self.assertTrue(self.js("split.compact"))
        self.assertFalse(self.js("split.sidebarShown"), "too narrow: it hides itself")
        self.js("split.toggle()")
        QTest.qWait(600)
        self.assertTrue(self.js("split.overlaid"))
        self.assertEqual(self.item("splitDetail").property("x"), 0, "over the detail, not squeezing it")
        self.assertEqual(self.item("splitSidebar").property("x"), 0)
        QTest.mouseClick(self.view, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier, QPoint(380, 240))
        self.assertFalse(self.js("split.sidebarShown"), "a click on the detail puts it away")
        self.view.resize(800, 480)
        QTest.qWait(600)
        self.assertTrue(self.js("split.sidebarShown"), "with room again, as it was")
        self.js("split.toggle()")
        self.view.resize(420, 480)
        QTest.qWait(50)
        self.view.resize(800, 480)
        QTest.qWait(50)
        self.assertFalse(self.js("split.sidebarShown"), "hidden by choice stays hidden")


if __name__ == "__main__":
    unittest.main()
