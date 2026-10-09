// A glass panel over the window, pointing at what opened it; a click outside
// or Escape closes it. Put it on the window's overlay:
//   Popover { id: pop; parent: overlay; panelWidth: 260; …content… }
//   pop.openAt(item, x, y)
import QtQuick
import QtQuick.Window
import "../../lib"
import "../../lib/theme"

Item {
    id: pop
    anchors.fill: parent
    visible: shown || panel.opacity > 0.001
    property bool shown: false
    property Item returnFocus: null
    z: 200
    property real panelWidth: 260
    property real panelHeight: content.childrenRect.height + 24
    property bool modal: true
    default property alias content: content.data
    readonly property alias panel: panel
    signal closed()

    function openAt(from, x, y) {
        const p = from.mapToItem(pop, x, y)
        returnFocus = from
        const above = p.y + panel.height + 8 > height
        panel.x = Math.max(8, Math.min(p.x, width - panel.width - 8))
        panel.y = above ? Math.max(8, p.y - panel.height - 8) : p.y
        panel.transformOrigin = above ? Item.Bottom : Item.Top
        shown = true
        panel.forceActiveFocus()
    }
    function close() {
        if (!shown) return
        shown = false
        closed()
        const origin = returnFocus
        returnFocus = null
        if (origin && origin.visible && origin.enabled) origin.forceActiveFocus()
    }

    MouseArea {
        anchors.fill: parent
        enabled: pop.modal && pop.shown
        acceptedButtons: Qt.AllButtons
        onPressed: pop.close()
    }
    Item {
        id: panel
        objectName: "designPopoverPanel"
        width: Math.min(pop.panelWidth, Math.max(0, pop.width - 16))
        height: Math.min(pop.panelHeight, Math.max(0, pop.height - 16))
        opacity: pop.shown ? 1 : 0
        scale: pop.shown || Theme.reduceMotion ? 1 : 0.965
        Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 0 : (pop.shown ? 135 : 105) } }
        Behavior on scale {
            enabled: !Theme.reduceMotion
            NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
        }
        focus: true
        Keys.onEscapePressed: pop.close()
        Rectangle {
            anchors.fill: parent
            radius: 14
            color: Theme.windowBg
            opacity: 0.97
        }
        Glass { anchors.fill: parent; radius: 14; role: "menu" }
        MouseArea { anchors.fill: parent; enabled: pop.shown }
        Item {
            id: content
            anchors { fill: parent; margins: 12 }
        }
    }
}
