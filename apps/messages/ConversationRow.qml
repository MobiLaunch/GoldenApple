// One conversation in the sidebar: the avatar, the name and time on one line,
// two lines of the latest message below, and a blue dot while it's unread.
// The selected row is the accent with white text, as in Messages.
import QtQuick
import "../lib"
import "../lib/theme"

Item {
    id: row
    property var thread: ({})
    property bool selected: false
    signal clicked()
    signal menuRequested(Item item, real x, real y)
    height: 68
    readonly property var last: (thread.messages || [])[(thread.messages || []).length - 1] ?? null

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: row.selected ? Theme.accent : hover.hovered ? Theme.fill : "transparent"
    }
    Rectangle {
        visible: !!row.thread.unread && !row.selected
        anchors { left: parent.left; leftMargin: 3; verticalCenter: parent.verticalCenter }
        width: 9; height: 9; radius: 4.5
        color: Theme.accentBlue
    }
    Avatar {
        id: face
        anchors { left: parent.left; leftMargin: 16; verticalCenter: parent.verticalCenter }
        size: 40
        name: row.thread.name || ""
        group: !!row.thread.is_group
    }
    Text {
        id: when
        anchors { right: parent.right; rightMargin: 10; top: parent.top; topMargin: 11 }
        text: app.listTime(row.thread.last_ts)
        color: row.selected ? "#d9ffffff" : Theme.secondaryLabel
        font { family: Theme.fontUi; pixelSize: 11 }
    }
    Text {
        anchors { left: face.right; leftMargin: 10; right: when.left; rightMargin: 6; top: parent.top; topMargin: 10 }
        text: row.thread.name || ""
        elide: Text.ElideRight
        color: row.selected ? "#ffffff" : Theme.label
        font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold }
    }
    Text {
        anchors { left: face.right; leftMargin: 10; right: parent.right; rightMargin: 10; top: parent.top; topMargin: 28 }
        text: row.last ? (row.last.outgoing ? "You: " : (row.thread.is_group && row.last.sender ? row.last.sender.split(" ")[0] + ": " : "")) + row.last.body : ""
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        maximumLineCount: 2
        elide: Text.ElideRight
        color: row.selected ? "#e6ffffff" : Theme.secondaryLabel
        font { family: Theme.fontUi; pixelSize: 12 }
    }
    HoverHandler { id: hover }
    TapHandler {
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onTapped: (p, button) => button === Qt.RightButton ? row.menuRequested(row, p.position.x, p.position.y) : row.clicked()
    }
}
