// Artists: the list on the left, the chosen artist's albums on the right.
import QtQuick
import "../lib/theme"

Item {
    id: page
    property var artists: []
    property var player
    property int selected: 0
    signal openAlbum(var album)
    readonly property var artist: artists[selected] ?? null

    ListView {
        id: list
        width: 240; height: parent.height
        topMargin: 36; bottomMargin: 90
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: page.artists
        delegate: Item {
            required property var modelData
            required property int index
            x: 16; width: list.width - 24; height: 48
            Rectangle {
                anchors.fill: parent; radius: 8
                color: index === page.selected ? "#fa2d48" : (Theme.dark ? "#ffffff" : "#000000")
                opacity: index === page.selected ? 1 : artistHover.hovered ? 0.04 : 0
            }
            Artwork {
                x: 8; anchors.verticalCenter: parent.verticalCenter
                width: 34; height: 34; round: true
                maskColor: index === page.selected ? "#fa2d48" : Theme.contentBg
                source: modelData.art
            }
            Text {
                x: 52; anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 60; elide: Text.ElideRight
                text: modelData.name
                color: index === page.selected ? "#ffffff" : Theme.label
                font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.Medium }
            }
            HoverHandler { id: artistHover }
            TapHandler { onTapped: page.selected = index }
        }
    }
    Rectangle { x: list.width; width: 0.5; height: parent.height; color: Theme.separator }
    AlbumsPage {
        x: list.width + 1; width: parent.width - x; height: parent.height
        title: page.artist?.name ?? ""
        albums: page.artist?.albums ?? []
        player: page.player
        topMargin: 14
        onOpenAlbum: (a) => page.openAlbum(a)
    }
}
