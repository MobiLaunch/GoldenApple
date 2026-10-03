// A glass panel over the window, pointing at what opened it; a click outside
// or Escape closes it. Put it on the window's overlay:
//   Popover { id: pop; parent: overlay; panelWidth: 260; …content… }
//   pop.openAt(item, x, y)
import QtQuick
import "../../lib"
import "../../lib/theme"

Item {
    id: pop
    anchors.fill: parent
    visible: false
    z: 200
    property real panelWidth: 260
    property real panelHeight: content.childrenRect.height + 24
    property bool modal: true
    default property alias content: content.data
    readonly property alias panel: panel
    signal closed()

    function openAt(from, x, y) {
        const p = from.mapToItem(pop, x, y)
        panel.x = Math.max(8, Math.min(p.x, width - panel.width - 8))
        panel.y = p.y + panel.height + 8 > height ? Math.max(8, p.y - panel.height - 8) : p.y
        visible = true
        panel.forceActiveFocus()
    }
    function close() { if (visible) { visible = false; closed() } }

    MouseArea {
        anchors.fill: parent
        enabled: pop.modal
        acceptedButtons: Qt.AllButtons
        onPressed: pop.close()
    }
    Item {
        id: panel
        width: pop.panelWidth
        height: Math.min(pop.panelHeight, pop.height - 16)
        focus: true
        Keys.onEscapePressed: pop.close()
        Rectangle {
            anchors.fill: parent
            radius: 14
            color: Theme.windowBg
            opacity: 0.92
        }
        Glass { anchors.fill: parent; radius: 14; role: "menu" }
        MouseArea { anchors.fill: parent }
        Item {
            id: content
            anchors { fill: parent; margins: 12 }
        }
    }
}
