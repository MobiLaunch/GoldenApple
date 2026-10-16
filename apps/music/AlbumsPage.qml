// A grid of albums (Albums, Recently Added, an artist's albums).
import QtQuick
import "../lib"
import "../lib/theme"

GridView {
    id: grid
    Scroller { parent: grid; flickable: grid }
    property string title
    property var albums: []
    property var player
    signal openAlbum(var album)

    readonly property real tile: 170
    readonly property int columns: Math.max(1, Math.floor((width - 56 + 22) / (tile + 22)))
    cellWidth: (width - 56) / columns
    cellHeight: tile + 44 + 24
    leftMargin: 28; rightMargin: 28; bottomMargin: 90
    boundsBehavior: Flickable.StopAtBounds
    clip: true
    model: albums

    header: Item {
        width: grid.width - 56; height: grid.title ? 70 : 20
        Text {
            y: 22
            visible: !!grid.title
            text: grid.title
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: 26; weight: Font.Bold }
        }
    }
    delegate: Item {
        required property var modelData
        width: grid.cellWidth; height: grid.cellHeight
        AlbumTile {
            size: Math.min(grid.tile, grid.cellWidth - 22)
            album: modelData
            onOpen: grid.openAlbum(modelData)
            onPlay: grid.player.playList(modelData.tracks, 0)
        }
    }
}
