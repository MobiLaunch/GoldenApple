// A context or pop-up menu inside the window, on AppWindow's overlay layer:
//   PopupMenu { id: menu; parent: win.overlay }
//   menu.popup(item, x, y, [{ text: "Play Next", action: () => … }, { separator: true }, …])
// The menu itself is MenuList (see there for the item format). Clicking
// outside or pressing Escape closes it; a long list scrolls, keeping
// `scrollTo` (an index) in view and highlighted. It grows out of the point it opened from and
// fades away once the chosen row has flashed.
import QtQuick
import "theme"

Item {
    id: menu
    anchors.fill: parent
    visible: false
    z: 100
    property var items: []
    property real menuWidth: 200
    property Item returnFocus: null
    readonly property alias list: box
    property alias selected: box.selected

    function popup(from, x, y, list, scrollTo) {
        // Reopening during a fade must not later execute the old menu action.
        vanish.stop()
        vanish.action = null
        appear.stop()
        box.cancelPending()
        returnFocus = from
        items = list
        const p = from.mapToItem(menu, x, y)
        box.x = Math.max(6, Math.min(p.x, width - box.width - 6))
        box.y = Math.max(6, Math.min(p.y, height - box.height - 6))
        box.transformOrigin = p.y > box.y + box.height / 2 ? Item.Bottom : Item.Top
        box.opacity = 1
        visible = true
        appear.restart()
        box.forceActiveFocus()
        // Opened by the pointer, nothing is highlighted until the pointer or an
        // arrow key picks a row; a pop-up button opens on its current item.
        box.selected = -1
        if (scrollTo !== undefined && scrollTo >= 0) box.scrollTo(scrollTo)
    }
    function close() {
        appear.stop()
        vanish.stop()
        vanish.action = null
        box.cancelPending()
        visible = false
        if (returnFocus && returnFocus.visible && returnFocus.enabled) returnFocus.forceActiveFocus()
    }

    NumberAnimation {
        id: appear
        target: box; property: "scale"; from: Theme.reduceMotion ? 1 : 0.9; to: 1
        duration: Theme.reduceMotion ? 0 : Theme.popover.duration
        easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.popover.curve
    }
    SequentialAnimation {
        id: vanish
        property var action
        NumberAnimation { target: box; property: "opacity"; to: 0; duration: Theme.reduceMotion ? 0 : 140 }
        ScriptAction { script: { const a = vanish.action; menu.close(); if (a) a() } }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: menu.close()
        onWheel: menu.close()
    }
    MenuList {
        id: box
        items: menu.items
        minimumWidth: Math.min(menu.menuWidth, menu.width - 12)
        maximumWidth: Math.max(minimumWidth, Math.min(360, menu.width - 12))
        height: Math.max(0, Math.min(implicitHeight, menu.height - 12))
        Keys.onTabPressed: menu.close()
        Keys.onBacktabPressed: menu.close()
        onDismissed: menu.close()
        onChosen: (item) => { vanish.action = item.action; vanish.restart() }
    }
}
