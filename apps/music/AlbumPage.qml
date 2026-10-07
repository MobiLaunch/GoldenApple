// An album (or playlist): big art, title, artist, Play and Shuffle, and the
// track list, as in Music on the Mac.
import QtQuick
import "../lib"
import "../lib/theme"

ListView {
    id: page
    property string title
    property string subtitle            // artist, in red
    property string detail              // "2026", "Playlist"
    property url art
    property var tracks: []
    property bool numbered: true
    property var player
    signal songMenu(var track, var list, Item from, real x, real y)

    readonly property int totalSeconds: tracks.reduce((s, t) => s + (t.seconds || 0), 0)
    function time(s) { s = Math.round(s); return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0") }

    boundsBehavior: Flickable.StopAtBounds
    clip: true
    model: tracks
    bottomMargin: 90

    header: Item {
        width: page.width; height: 330
        Artwork {
            x: 28; y: 28
            width: 260; height: 260; radius: 10
            source: page.art
        }
        Column {
            x: 316; anchors.bottom: parent.bottom; anchors.bottomMargin: 42
            width: page.width - 316 - 28
            spacing: 2
            Text {
                width: parent.width; elide: Text.ElideRight
                text: page.title
                color: Theme.label
                font { family: Theme.fontUi; pixelSize: 26; weight: Font.Bold }
            }
            Text {
                width: parent.width; elide: Text.ElideRight
                text: page.subtitle
                color: "#fa2d48"
                font { family: Theme.fontUi; pixelSize: Theme.fs(22) }
            }
            Text {
                text: page.detail
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: Theme.fs(11); weight: Font.DemiBold }
            }
            Item { width: 1; height: 16 }
            Row {
                spacing: 10
                Repeater {
                    model: [{ t: "Play", s: "play", shuffle: false }, { t: "Shuffle", s: "shuffle", shuffle: true }]
                    delegate: Rectangle {
                        required property var modelData
                        width: 104; height: 30; radius: 7
                        color: Theme.dark ? "#2c2c2e" : "#ebebef"
                        opacity: page.tracks.length ? 1 : 0.5
                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            Symbol { anchors.verticalCenter: parent.verticalCenter; name: modelData.s; tone: "red"; size: 12 }
                            Text { text: modelData.t; color: "#fa2d48"; font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.DemiBold } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (!page.tracks.length) return
                                page.player.shuffle = modelData.shuffle
                                page.player.playList(page.tracks, modelData.shuffle ? Math.floor(Math.random() * page.tracks.length) : 0)
                            }
                        }
                    }
                }
            }
        }
    }
    delegate: Item {
        id: trackRow
        required property var modelData
        required property int index
        width: page.width; height: 38
        readonly property bool current: page.player.current?.path === modelData.path
        Rectangle {
            x: 20; width: parent.width - 40; height: parent.height
            radius: 6
            color: Theme.dark ? "#ffffff" : "#000000"
            opacity: trackRow.index % 2 === 0 ? (Theme.dark ? 0.04 : 0.028) : 0
        }
        Rectangle {
            x: 20; width: parent.width - 40; height: parent.height
            radius: 6
            color: Theme.dark ? "#ffffff" : "#000000"
            opacity: rowHover.hovered ? 0.05 : 0
        }
        Item {
            x: 28; width: 26; height: parent.height
            Text {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                visible: !trackRow.current && !rowHover.hovered
                text: page.numbered ? (trackRow.modelData.track || trackRow.index + 1) : trackRow.index + 1
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
            }
            Symbol {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                visible: trackRow.current || rowHover.hovered
                name: trackRow.current && !rowHover.hovered ? "speaker-wave" : "play"
                tone: "red"; size: 12
            }
        }
        Text {
            x: 68; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 68 - 130
            elide: Text.ElideRight
            text: trackRow.modelData.title + (page.numbered ? "" : "  ·  " + trackRow.modelData.artist)
            color: trackRow.current ? "#fa2d48" : Theme.label
            font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
        }
        Text {
            anchors { right: parent.right; rightMargin: 72; verticalCenter: parent.verticalCenter }
            text: page.time(trackRow.modelData.seconds)
            color: Theme.secondaryLabel
            font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
        }
        Item {
            anchors { right: parent.right; rightMargin: 30; verticalCenter: parent.verticalCenter }
            width: 30; height: 30
            Symbol { anchors.centerIn: parent; name: "ellipsis"; tone: "red"; size: 15; visible: rowHover.hovered }
            MouseArea {
                anchors.fill: parent
                onClicked: (m) => { const p = trackRow.mapFromItem(parent, m.x, m.y); page.songMenu(trackRow.modelData, page.tracks, trackRow, p.x, p.y) }
            }
        }
        HoverHandler { id: rowHover }
        TapHandler { onDoubleTapped: page.player.playList(page.tracks, trackRow.index) }
    }
    footer: Text {
        x: 28; topPadding: 14
        text: page.tracks.length + (page.tracks.length === 1 ? " song, " : " songs, ") + Math.round(page.totalSeconds / 60) + " minutes"
        color: Theme.secondaryLabel
        font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
    }
}
