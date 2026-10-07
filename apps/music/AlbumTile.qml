// An album in a grid: art, title, artist. Click opens it; the play button on
// hover plays it.
import QtQuick
import "../lib"
import "../lib/theme"

Item {
    id: tile
    property var album
    property real size: 170
    signal open()
    signal play()
    width: size; height: size + 44

    Artwork {
        id: cover
        width: tile.size; height: tile.size
        radius: 8
        source: tile.album?.art ?? ""
    }
    Rectangle {
        anchors { left: cover.left; bottom: cover.bottom; margins: 10 }
        width: 30; height: 30; radius: 15
        visible: hover.hovered
        color: "#d9ffffff"
        Symbol { anchors.centerIn: parent; anchors.horizontalCenterOffset: 1; name: "play"; tone: "red"; size: 13 }
        MouseArea { anchors.fill: parent; onClicked: tile.play() }
    }
    Text {
        y: tile.size + 6; width: tile.size
        elide: Text.ElideRight
        text: tile.album?.title ?? ""
        color: Theme.label
        font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.Medium }
    }
    Text {
        y: tile.size + 23; width: tile.size
        elide: Text.ElideRight
        text: tile.album?.artist ?? ""
        color: Theme.secondaryLabel
        font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
    }
    HoverHandler { id: hover }
    TapHandler { onTapped: tile.open() }
}
