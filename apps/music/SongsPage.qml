// Songs: every track in a table (title, artist, album, time), sortable by
// clicking a column.
import QtQuick
import "../lib"
import "../lib/theme"

Item {
    id: page
    property var tracks: []
    property var player
    property string sortKey: "title"
    signal songMenu(var track, var list, Item from, real x, real y)

    readonly property var sorted: tracks.slice().sort((a, b) => {
        if (sortKey === "seconds") return a.seconds - b.seconds
        return String(a[sortKey]).localeCompare(String(b[sortKey])) || a.track - b.track
    })
    function time(s) { s = Math.round(s); return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0") }
    readonly property real colTitle: 28 + 36
    readonly property real colArtist: colTitle + (width - 56 - 36 - 70) * 0.4
    readonly property real colAlbum: colArtist + (width - 56 - 36 - 70) * 0.3

    Text {
        x: 28; y: 36
        text: "Songs"
        color: Theme.label
        font { family: Theme.fontUi; pixelSize: 26; weight: Font.Bold }
    }
    Item {
        id: head
        y: 84; width: parent.width; height: 26
        Repeater {
            model: [{ t: "Title", k: "title", x: page.colTitle }, { t: "Artist", k: "artist", x: page.colArtist },
                    { t: "Album", k: "album", x: page.colAlbum }, { t: "Time", k: "seconds", x: page.width - 28 - 60 }]
            delegate: Row {
                required property var modelData
                x: modelData.x; height: head.height
                spacing: 3
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.t
                    color: page.sortKey === modelData.k ? Theme.label : Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: Theme.fs(11); weight: Font.DemiBold }
                }
                Symbol {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: page.sortKey === modelData.k
                    name: "chevron-down"; tone: "gray"; size: 9
                }
                TapHandler { onTapped: page.sortKey = modelData.k }
            }
        }
        Rectangle { x: 28; y: parent.height - 1; width: parent.width - 56; height: 0.5; color: Theme.separator }
    }
    ListView {
        id: list
        y: head.y + head.height; width: parent.width; height: parent.height - y
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        bottomMargin: 90
        model: page.sorted
        delegate: Item {
            id: songRow
            required property var modelData
            required property int index
            width: list.width; height: 40
            readonly property bool current: page.player.current?.path === modelData.path
            Rectangle {
                x: 20; width: parent.width - 40; height: parent.height; radius: 6
                color: Theme.dark ? "#ffffff" : "#000000"
                opacity: (songRow.index % 2 === 0 ? (Theme.dark ? 0.04 : 0.028) : 0) + (rowHover.hovered ? 0.04 : 0)
            }
            Artwork {
                x: 28; anchors.verticalCenter: parent.verticalCenter
                width: 28; height: 28; radius: 4
                maskColor: Qt.tint(Theme.contentBg, songRow.index % 2 === 0 ? (Theme.dark ? "#0affffff" : "#07000000") : "transparent")
                source: songRow.modelData.art
            }
            Repeater {
                model: [{ v: songRow.modelData.title, x: page.colTitle, w: page.colArtist - page.colTitle - 12 },
                        { v: songRow.modelData.artist, x: page.colArtist, w: page.colAlbum - page.colArtist - 12 },
                        { v: songRow.modelData.album, x: page.colAlbum, w: page.width - 28 - 70 - page.colAlbum - 12 },
                        { v: page.time(songRow.modelData.seconds), x: page.width - 28 - 60, w: 50 }]
                delegate: Text {
                    required property var modelData
                    required property int index
                    x: modelData.x; width: modelData.w
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: modelData.v
                    color: songRow.current && index === 0 ? "#fa2d48" : index === 0 ? Theme.label : Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
                }
            }
            HoverHandler { id: rowHover }
            TapHandler {
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onDoubleTapped: page.player.playList(page.sorted, songRow.index)
                onTapped: (p, button) => { if (button === Qt.RightButton) page.songMenu(songRow.modelData, page.sorted, songRow, p.position.x, p.position.y) }
            }
        }
    }
}
