// A context menu drawn inside the window, on AppWindow's overlay layer:
//   PopupMenu { id: menu; parent: win.overlay }
//   menu.popup(item, x, y, [{ text: "Play Next", action: () => … }, { separator: true }, …])
// Clicking outside or pressing Escape closes it. A long list scrolls, keeping
// `scrollTo` (an index) in view. It fades and grows in from where it opened.
import QtQuick
import "theme"

Item {
    id: menu
    anchors.fill: parent
    visible: false
    z: 100
    property var items: []
    property real menuWidth: 220

    function popup(from, x, y, list, scrollTo) {
        items = list
        const p = from.mapToItem(menu, x, y)
        box.x = Math.max(6, Math.min(p.x, width - box.width - 6))
        box.y = Math.max(6, Math.min(p.y, height - box.height - 6))
        flick.contentY = 0
        if (scrollTo > 0) {
            const at = list.slice(0, scrollTo).reduce((h, it) => h + (it.separator ? 11 : 24), 0)
            flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, at - flick.height / 2 + 12))
        }
        visible = true
        appear.restart()
        forceActiveFocus()
    }
    function close() { visible = false }
    ParallelAnimation {
        id: appear
        NumberAnimation { target: box; property: "opacity"; from: 0; to: 1; duration: 120 }
        NumberAnimation { target: box; property: "scale"; from: 0.94; to: 1; duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
    }
    Keys.onEscapePressed: close()

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: menu.close()
        onWheel: menu.close()
    }
    Rectangle {
        id: box
        width: menu.menuWidth
        implicitHeight: col.height + 10
        height: Math.min(implicitHeight, menu.height - 12)
        transformOrigin: Item.Top
        radius: Theme.radiusMenu
        color: Theme.dark ? "#f5323236" : "#faf6f6f8"
        border { width: 0.5; color: Theme.dark ? "#33ffffff" : "#26000000" }
        Rectangle { z: -1; anchors { fill: parent; topMargin: 4; bottomMargin: -8; leftMargin: -2; rightMargin: -2 } radius: parent.radius + 2; color: "#1f000000" }
        MouseArea { anchors.fill: parent }  // clicks inside don't close it
        Flickable {
            id: flick
            anchors { fill: parent; margins: 5 }
            contentHeight: col.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
        Column {
            id: col
            width: flick.width
            Repeater {
                model: menu.items
                delegate: Item {
                    id: entry
                    required property var modelData
                    readonly property bool sep: !!modelData.separator
                    readonly property bool on: !sep && modelData.enabled !== false
                    width: col.width
                    height: sep ? 11 : 24
                    Rectangle {
                        visible: entry.sep
                        anchors.centerIn: parent
                        width: parent.width - 18; height: 1
                        color: Theme.separator
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radiusMenuItem - 2
                        color: Theme.accent
                        visible: entry.on && hover.hovered
                    }
                    Text {
                        visible: !entry.sep
                        x: 12; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 24; elide: Text.ElideRight
                        text: entry.modelData.text ?? ""
                        color: entry.on && hover.hovered ? "#ffffff" : entry.on ? Theme.label : Theme.tertiaryLabel
                        font { family: Theme.fontUi; pixelSize: 13 }
                    }
                    HoverHandler { id: hover }
                    MouseArea {
                        anchors.fill: parent
                        enabled: entry.on
                        onClicked: { menu.close(); entry.modelData.action?.() }
                    }
                }
            }
        }
        }
    }
}
