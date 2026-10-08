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
    // Room for a submenu beside its row, sized before the menu opens (a
    // popup surface resized while open is dismissed); input only on what shows.
    readonly property real subRoom: items.some((it) => it && it.submenu) ? 300 : 0
    readonly property real subDepth: {
        let y = list.pad, deepest = 0
        for (const it of items) {
            if (it && it.submenu)
                deepest = Math.max(deepest, y + it.submenu.reduce((h, s) => h + list.rowHeight(s), 0) + 2 * list.pad)
            y += list.rowHeight(it)
        }
        return deepest
    }
    implicitWidth: menuWidth + subRoom + 24
    implicitHeight: Math.max(menuHeight, subDepth) + 28
    mask: Region {
        item: list
        Region { item: list.sub && list.sub.visible ? list.sub : null }
    }

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
        NumberAnimation { target: list; property: "opacity"; to: 0; duration: Theme.reduceMotion ? 0 : 140 }
        ScriptAction { script: { const a = vanish.action; vanish.action = null; if (a) a() } }
    }

    // What the menu's glass bends: the desktop under it, placed from the
    // surface it opens over and where it's anchored there.
    // Only the wallpaper: a menu's surface comes and goes with every opening,
    // and window captures made and dropped that often are what Quickshell
    // copes with least. Under a menu's tint the difference hardly shows.
    DesktopBackdrop {
        surface: menu
        includeWindows: false
        fixedAt: {
            const o = Backdrops.ownerOf(menu.anchor.window?.contentItem ?? null)
            return o && o.placed ? Qt.point(o.at.x + menu.anchor.rect.x, o.at.y + menu.anchor.rect.y) : null
        }
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
