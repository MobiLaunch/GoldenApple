// Search your library: songs, albums and artists as you type.
import QtQuick
import "../lib"
import "../lib/theme"

Flickable {
    id: page
    property var lib
    property var player
    property string query: ""
    signal openAlbum(var album)
    signal songMenu(var track, var list, Item from, real x, real y)
    function focusField() { field.input.forceActiveFocus() }

    readonly property string q: query.trim().toLowerCase()
    readonly property var songs: q ? lib.tracks.filter((t) => (t.title + " " + t.artist + " " + t.album).toLowerCase().includes(q)).slice(0, 30) : []
    readonly property var albums: q ? lib.albums.filter((a) => (a.title + " " + a.artist).toLowerCase().includes(q)).slice(0, 20) : []

    contentHeight: col.height + 90
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    Column {
        id: col
        x: 28; y: 22
        width: page.width - 56
        spacing: 18
        Text {
            text: "Search"
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: 26; weight: Font.Bold }
        }
        TextField {
            id: field
            width: parent.width
            height: 36
            search: true
            placeholder: "Artists, Songs, Albums"
            text: page.query
            onTextChanged: page.query = text
            input.Keys.onEscapePressed: text = ""
        }
        Text {
            visible: !!page.q && !page.songs.length && !page.albums.length
            text: "No results for “" + page.query + "”"
            color: Theme.secondaryLabel
            font { family: Theme.fontUi; pixelSize: Theme.fs(15) }
        }
        SectionHeader { visible: page.albums.length > 0; text: "Albums"; more: false }
        ListView {
            visible: page.albums.length > 0
            width: parent.width; height: 170 + 46
            orientation: ListView.Horizontal
            spacing: 18
            clip: true
            model: page.albums
            delegate: AlbumTile {
                required property var modelData
                album: modelData
                onOpen: page.openAlbum(modelData)
                onPlay: page.player.playList(modelData.tracks, 0)
            }
        }
        SectionHeader { visible: page.songs.length > 0; text: "Songs"; more: false }
        Grid {
            id: songGrid
            visible: page.songs.length > 0
            columns: 2; columnSpacing: 22
            width: parent.width
            Repeater {
                model: page.songs
                delegate: SongRow {
                    id: songRow
                    required property var modelData
                    required property int index
                    width: (songGrid.width - songGrid.columnSpacing) / 2
                    track: modelData
                    current: page.player.current?.path === modelData.path
                    onPlay: page.player.playList(page.songs, index)
                    onMenu: (mx, my) => page.songMenu(modelData, page.songs, songRow, mx, my)
                }
            }
        }
    }
}
