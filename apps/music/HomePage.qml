// Home: what's new in your library. Large cards for the latest albums, the
// latest songs in columns, and recently added albums.
import Quickshell
import QtQuick
import "../lib"
import "../lib/theme"

Flickable {
    id: page
    property var lib
    property var player
    signal openAlbum(var album)
    signal go(string page)
    signal songMenu(var track, var list, Item from, real x, real y)

    contentHeight: col.height + 90
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    Column {
        id: col
        x: 28; y: 22
        width: page.width - 28
        spacing: 22

        Text {
            text: "Home"
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: 26; weight: Font.Bold }
        }

        // Empty library
        Column {
            visible: page.lib.loaded && page.lib.tracks.length === 0
            spacing: 10
            Text {
                text: page.lib.scanning ? "Looking for music…" : "Your library is empty"
                color: Theme.label
                font { family: Theme.fontUi; pixelSize: 17; weight: Font.DemiBold }
            }
            Text {
                width: 420; wrapMode: Text.WordWrap
                text: "Put songs in your Music folder (" + page.lib.musicDir.replace(Quickshell.env("HOME"), "~")
                      + ") and they'll appear here. Or listen to Radio."
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: 13 }
            }
            Rectangle {
                width: openLabel.width + 28; height: 28; radius: 14
                color: openArea.pressed ? Qt.darker("#fa2d48", 1.15) : "#fa2d48"
                scale: openArea.pressed ? 0.95 : 1
                Behavior on scale { Spring { spring: Theme.snappy } }
                Text { id: openLabel; anchors.centerIn: parent; text: "Open Music Folder"; color: "#ffffff"; font { family: Theme.fontUi; pixelSize: 13; weight: Font.Medium } }
                MouseArea { id: openArea; anchors.fill: parent; onClicked: Quickshell.execDetached(["sh", "-c", "mkdir -p \"$1\" && xdg-open \"$1\"", "sh", page.lib.musicDir]) }
            }
        }

        ListView {
            visible: page.lib.albums.length > 0
            width: parent.width; height: 272
            orientation: ListView.Horizontal
            spacing: 18
            rightMargin: 28
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: page.lib.recentAlbums.slice(0, 6)
            delegate: HeroCard {
                required property var modelData
                album: modelData
                kicker: modelData.year && Number(modelData.year) >= new Date().getFullYear() ? "New Album" : "Recently Added"
                onOpen: page.openAlbum(modelData)
                onPlay: page.player.playList(modelData.tracks, 0)
            }
        }

        Column {
            visible: page.lib.tracks.length > 0
            width: parent.width - 28
            spacing: 8
            SectionHeader { text: "Latest Songs"; onClicked: page.go("songs") }
            Grid {
                id: songGrid
                columns: 3
                columnSpacing: 22
                width: parent.width
                flow: Grid.TopToBottom
                rows: 4
                readonly property var songs: page.lib.recentTracks.slice(0, 12)
                Repeater {
                    model: songGrid.songs
                    delegate: SongRow {
                        id: songRow
                        required property var modelData
                        required property int index
                        width: (songGrid.width - 2 * songGrid.columnSpacing) / 3
                        track: modelData
                        current: page.player.current?.path === modelData.path
                        onPlay: page.player.playList(songGrid.songs, index)
                        onMenu: (mx, my) => page.songMenu(modelData, songGrid.songs, songRow, mx, my)
                    }
                }
            }
        }

        Column {
            visible: page.lib.albums.length > 0
            width: parent.width
            spacing: 10
            SectionHeader { text: "Recently Added"; onClicked: page.go("recent") }
            ListView {
                width: parent.width; height: 170 + 46
                orientation: ListView.Horizontal
                spacing: 18
                rightMargin: 28
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: page.lib.recentAlbums.slice(0, 20)
                delegate: AlbumTile {
                    required property var modelData
                    album: modelData
                    onOpen: page.openAlbum(modelData)
                    onPlay: page.player.playList(modelData.tracks, 0)
                }
            }
        }
    }
}
