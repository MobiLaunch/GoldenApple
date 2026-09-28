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
    property int selected: -1
    property Item returnFocus: null
    function available(i) { return i >= 0 && i < items.length && !items[i].separator && items[i].enabled !== false }
    function select(i) {
        selected = i
        const row = entries.itemAt(i)
        if (row) flick.contentY = Math.max(0, Math.min(Math.max(0, flick.contentHeight - flick.height),
            row.y < flick.contentY ? row.y : row.y + row.height > flick.contentY + flick.height ? row.y + row.height - flick.height : flick.contentY))
    }
    function move(step) {
        for (let n = 1; n <= items.length; n++) {
            const i = ((selected < 0 ? (step > 0 ? -1 : 0) : selected) + step * n + items.length) % items.length
            if (available(i)) { select(i); return }
        }
    }
    function activate() {
        if (!available(selected)) return
        const action = items[selected].action
        close()
        if (action) action()
    }
    Keys.onDownPressed: move(1)
    Keys.onUpPressed: move(-1)
    Keys.onReturnPressed: activate()
    Keys.onEnterPressed: activate()
    Keys.onSpacePressed: activate()
    Keys.onTabPressed: close()
    Keys.onBacktabPressed: close()

    function popup(from, x, y, list, scrollTo) {
        returnFocus = from
        selected = -1
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
        if (available(scrollTo)) select(scrollTo); else move(1)
    }
    function close() { visible = false; if (returnFocus && returnFocus.visible && returnFocus.enabled) returnFocus.forceActiveFocus() }
    ParallelAnimation {
        id: appear
        NumberAnimation { target: box; property: "opacity"; from: 0; to: 1; duration: 120 }
        NumberAnimation { target: box; property: "scale"; from: 0.94; to: 1; duration: Theme.reduceMotion ? 0 : 220; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
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
        width: Math.max(0, Math.min(menu.menuWidth, menu.width - 12))
        implicitHeight: col.height + 10
        height: Math.max(0, Math.min(implicitHeight, menu.height - 12))
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
                id: entries
                model: menu.items
                delegate: Item {
                    id: entry
                    required property var modelData
                    required property int index
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
                        visible: entry.on && menu.selected === entry.index
                    }
                    Text {
                        visible: !entry.sep
                        x: 12; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 24; elide: Text.ElideRight
                        text: entry.modelData.text ?? ""
                        color: entry.on && menu.selected === entry.index ? "#ffffff" : entry.on ? Theme.label : Theme.tertiaryLabel
                        font { family: Theme.fontUi; pixelSize: 13 }
                    }
                    HoverHandler { id: hover; onHoveredChanged: if (hovered && entry.on) menu.select(entry.index) }
                    MouseArea {
                        anchors.fill: parent
                        enabled: entry.on
                        onClicked: { menu.selected = entry.index; menu.activate() }
                    }
                }
            }
        }
        }
    }
}

