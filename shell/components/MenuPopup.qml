// A shell menu in its own surface: the menu bar's menus and the desktop, Dock
// and Applications context menus. The menu is the shared MenuList, the same
// one apps use (see there for the item format; "-" is a separator).
// Menu-bar menus (`instant`) appear at once, context menus grow out of the
// pointer; either fades once the chosen row has flashed.
import Quickshell
import QtQuick
import "../ui" as Shared
import "../ui/theme"

PopupWindow {
    id: menu
    property var items: []
    property bool open: false
    property bool instant: false
    readonly property alias list: list
    property alias growFrom: list.transformOrigin      // the corner nearest the pointer
    signal dismissed()

    visible: open || vanish.running
    color: "transparent"
    // The menu's own size, for callers placing it; the surface adds room
    // right and below for the shadow, and takes input only on the menu.
    readonly property real menuWidth: list.width
    readonly property real menuHeight: list.implicitHeight
    implicitWidth: menuWidth + 24
    implicitHeight: menuHeight + 28
    mask: Region { item: list }

    onOpenChanged: if (open) {
        vanish.stop()
        list.opacity = 1
        list.selected = -1
        list.scale = 1
        if (!instant && !Theme.reduceMotion) appear.restart()
        list.forceActiveFocus()
    }

    NumberAnimation {
        id: appear
        target: list; property: "scale"; from: 0.9; to: 1
        duration: Theme.popover.duration
        easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.popover.curve
    }

    SequentialAnimation {
        id: vanish
        property var action
        NumberAnimation { target: list; property: "opacity"; to: 0; duration: Theme.reduceMotion ? 0 : 160 }
        ScriptAction { script: { const a = vanish.action; vanish.action = null; if (a) a() } }
    }

    Shared.MenuList {
        id: list
        items: menu.items
        minimumWidth: 220
        transformOrigin: Item.TopLeft
        onDismissed: { menu.open = false; menu.dismissed() }
        onChosen: (item) => {
            vanish.action = item.action
            vanish.restart()            // first, so the surface stays up while it fades
            menu.open = false
            menu.dismissed()
        }
    }
}
