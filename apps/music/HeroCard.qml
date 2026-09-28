// A large featured card on Home: the album's colour (averaged from its art)
// fills the card, with the art on the right and a line about it on the left,
// like Music's editorial cards.
import QtQuick
import "../lib/theme"

Item {
    id: hero
    property var album
    property string kicker: "Recently Added"
    signal open()
    signal play()
    width: 380; height: 272

    property color tone: Theme.dark ? "#3a3a3c" : "#d1d1d6"
    readonly property bool lightTone: (0.299 * tone.r + 0.587 * tone.g + 0.114 * tone.b) > 0.62

    Text {
        text: hero.kicker.toUpperCase()
        color: Theme.secondaryLabel
        font { family: Theme.fontUi; pixelSize: 10; weight: Font.DemiBold; letterSpacing: 0.2 }
    }
    Text {
        y: 13; width: parent.width; elide: Text.ElideRight
        text: hero.album?.title ?? ""
        color: Theme.label
        font { family: Theme.fontUi; pixelSize: 14; weight: Font.Medium }
    }
    Text {
        y: 31; width: parent.width; elide: Text.ElideRight
        text: hero.album?.artist ?? ""
        color: Theme.secondaryLabel
        font { family: Theme.fontUi; pixelSize: 14 }
    }

    Rectangle {
        id: card
        y: 54; width: parent.width; height: parent.height - 54
        radius: 10
        color: hero.tone
        Behavior on color { ColorAnimation { duration: 300 } }
        clip: true

        // Samples the art down to 6×6 pixels and averages them.
        Canvas {
            id: sampler
            anchors.centerIn: cover          // hidden under the art
            width: 6; height: 6
            readonly property string src: hero.album?.art ?? ""
            onSrcChanged: if (src) loadImage(src)
            onImageLoaded: requestPaint()
            onPaint: {
                if (!src || !isImageLoaded(src)) return
                const ctx = getContext("2d")
                ctx.drawImage(src, 0, 0, 6, 6)
                const d = ctx.getImageData(0, 0, 6, 6).data
                let r = 0, g = 0, b = 0
                for (let i = 0; i < d.length; i += 4) { r += d[i]; g += d[i + 1]; b += d[i + 2] }
                const n = d.length / 4 * 255
                hero.tone = Qt.rgba(r / n * 0.9, g / n * 0.9, b / n * 0.9, 1)
            }
        }
        Artwork {
            id: cover
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom; margins: 14 }
            width: height
            radius: 6
            maskColor: hero.tone
            source: hero.album?.art ?? ""
        }
        Text {
            anchors { left: parent.left; bottom: parent.bottom; margins: 14 }
            width: parent.width - parent.height - 14
            wrapMode: Text.WordWrap
            text: hero.album ? hero.album.tracks.length + (hero.album.tracks.length === 1 ? " song" : " songs")
                  + (hero.album.year ? " · " + hero.album.year : "") : ""
            color: hero.lightTone ? "#cc000000" : "#e6ffffff"
            font { family: Theme.fontUi; pixelSize: 12; weight: Font.Medium }
        }
        Rectangle {
            anchors { left: parent.left; top: parent.top; margins: 14 }
            width: 36; height: 36; radius: 18
            color: hero.lightTone ? "#1f000000" : "#33ffffff"
            Text {
                anchors.centerIn: parent; anchors.horizontalCenterOffset: 1
                text: "▶"; color: hero.lightTone ? "#000000" : "#ffffff"
                font.pixelSize: 14
            }
            MouseArea { anchors.fill: parent; onClicked: hero.play() }
        }
        TapHandler { onTapped: hero.open() }
    }
}
