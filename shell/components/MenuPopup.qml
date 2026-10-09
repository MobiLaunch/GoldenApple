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

    // A popup surface must not change size or place while it's up: Qt makes
    // it again, draws before the compositor has configured the new one, and
    // the compositor drops the whole shell for it (xdg_surface "has never
    // been configured", then Quickshell exits and restarts). That happened
    // going from one menu-bar menu to the next, right-clicking a second Dock
    // icon or another spot on the desktop, or when a menu's items changed
    // while it was open. So what's shown is fixed while the menu is up; a
    // change that would move or resize it closes the surface and opens it
    // again a moment later, with the new items, where it now belongs.
    property var shown: items
    property bool reopening: false
    // Ignore a delayed focus-clear from the OLD surface during menu switching.
    // The new popup grabs focus again as soon as its new surface appears.
    property bool suppressClear: false
    visible: (open || vanish.running) && !reopening
    color: "transparent"
    function shape(list) {
        return JSON.stringify((list ?? []).map((it) => typeof it === "string" ? it
            : [it?.label ?? "", it?.header ?? "", it?.symbol ?? "", it?.shortcut ?? "", !!it?.submenu, (it?.submenu ?? []).length]))
    }
    onItemsChanged: {
        if (!open) { shown = items; return }
        if (shape(items) === shape(shown)) shown = items       // same rows: actions and ticks refreshed in place
        else reopen()
    }
    readonly property string place: (anchor.window ? "w" : "") + "," + anchor.rect.x + "," + anchor.rect.y
    onPlaceChanged: if (open && visible) reopen()
    function reopen() {
        reopening = true
        suppressClear = true
        clearGrace.restart()
        reopenTimer.restart()
    }
    Timer {
        id: clearGrace
        interval: 240
        onTriggered: menu.suppressClear = false
    }
    Timer {
        id: reopenTimer
        interval: 40
        onTriggered: {
            menu.shown = menu.items
            menu.reopening = false
            if (menu.open) list.forceActiveFocus()
        }
    }
    // The menu's own size, for callers placing it; the surface adds room
    // right and below for the shadow, and takes input only on the menu.
    readonly property real menuWidth: list.width
    readonly property real menuHeight: list.implicitHeight
    // Room for a submenu beside its row, sized before the menu opens (a
    // popup surface resized while open is dismissed); input only on what shows.
    readonly property real subRoom: shown.some((it) => it && it.submenu) ? 300 : 0
    readonly property real subDepth: {
        let y = list.pad, deepest = 0
        for (const it of shown) {
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
        clearGrace.stop()
        suppressClear = false
        reopenTimer.stop()
        reopening = false
        shown = items
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
        items: menu.shown
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
