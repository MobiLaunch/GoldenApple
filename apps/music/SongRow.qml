// A song in a list: small art, title and artist, and a ⋯ menu button.
import QtQuick
import "../lib"
import "../lib/theme"

Item {
    id: row
    property var track
    property bool current: false
    property bool separator: true
    signal play()
    signal menu(real x, real y)
    height: 46

    Rectangle {
        visible: row.separator
        x: 48; width: parent.width - 48; height: 0.5
        color: Theme.separator
    }
    Rectangle {
        anchors { fill: parent; topMargin: 1 }
        radius: 6
        color: Theme.dark ? "#ffffff" : "#000000"
        opacity: hover.hovered ? 0.04 : 0
    }
    Artwork {
        x: 2; anchors.verticalCenter: parent.verticalCenter
        width: 36; height: 36; radius: 4
        source: row.track?.art ?? ""
        Rectangle {
            anchors.fill: parent; radius: 4
            visible: row.current || hover.hovered
            color: "#66000000"
            Symbol { anchors.centerIn: parent; name: row.current ? "speaker-wave" : "play"; tone: "white"; size: 14 }
        }
    }
    Column {
        x: 48; anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 48 - 34
        Text {
            width: parent.width; elide: Text.ElideRight
            text: row.track?.title ?? ""
            color: row.current ? "#fa2d48" : Theme.label
            font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
        }
        Text {
            width: parent.width; elide: Text.ElideRight
            text: row.track?.artist ?? ""
            color: Theme.secondaryLabel
            font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
        }
    }
    Item {
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        width: 30; height: 30
        Symbol { anchors.centerIn: parent; name: "ellipsis"; tone: "red"; size: 15; opacity: hover.hovered ? 1 : 0.8 }
        MouseArea {
            anchors.fill: parent
            onClicked: (m) => { const p = row.mapFromItem(parent, m.x, m.y); row.menu(p.x, p.y) }
        }
    }
    HoverHandler { id: hover }
    TapHandler { onTapped: row.play() }
}
