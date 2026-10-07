// The floating player, as in Music on macOS 27: a glass capsule over the bottom
// of the content with transport controls, the song and its progress, and the
// queue and volume buttons.
import QtQuick
import "../lib"
import "../lib/theme"

Item {
    id: bar
    property var player
    signal showQueue()
    signal openAlbum(var track)
    width: 580; height: 46

    readonly property color glass: Theme.dark ? "#f22a2a2d" : "#f5fbfbfd"

    // Shadow, then glass.
    Rectangle { anchors { fill: parent; topMargin: 3; bottomMargin: -4; leftMargin: 2; rightMargin: 2 } radius: height / 2; color: Theme.dark ? "#59000000" : "#1a000000" }
    Rectangle { anchors { fill: parent; topMargin: 1; bottomMargin: -1 } radius: height / 2; color: Theme.dark ? "#33000000" : "#0d000000" }
    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: bar.glass
        border { width: 0.5; color: Theme.dark ? "#26ffffff" : "#1a000000" }
    }

    component Btn: Item {
        id: b
        property string symbol
        property real size: 15
        property bool on: false
        property bool dim: false
        signal clicked()
        width: size + 14; height: bar.height
        Symbol {
            anchors.centerIn: parent
            name: b.symbol; size: b.size
            tone: b.on ? "red" : "auto"
            opacity: b.dim && !b.on ? 0.45 : bh.hovered ? 1 : 0.85
        }
        HoverHandler { id: bh }
        MouseArea { anchors.fill: parent; onClicked: b.clicked() }
    }

    Row {
        id: transport
        x: 14; height: parent.height
        spacing: 0
        Btn { symbol: "shuffle"; size: 13; dim: true; on: bar.player.shuffle; onClicked: bar.player.shuffle = !bar.player.shuffle }
        Btn { symbol: "backward"; onClicked: bar.player.previous() }
        Btn { symbol: bar.player.playing ? "pause" : "play"; size: 19; onClicked: bar.player.toggle() }
        Btn { symbol: "forward"; onClicked: bar.player.next() }
        Btn {
            symbol: "repeat"; size: 13; dim: true; on: bar.player.repeat !== "off"
            onClicked: bar.player.repeat = bar.player.repeat === "off" ? "all" : bar.player.repeat === "all" ? "one" : "off"
            Text {
                visible: bar.player.repeat === "one"
                anchors { right: parent.right; rightMargin: 3; top: parent.top; topMargin: 11 }
                text: "1"; color: "#fa2d48"
                font { family: Theme.fontUi; pixelSize: Theme.fs(8); weight: Font.Bold }
            }
        }
    }

    // Now playing
    Item {
        id: info
        x: transport.x + transport.width + 8
        width: parent.width - x - tools.width - 16
        height: parent.height
        Artwork {
            id: nowArt
            x: 0; anchors.verticalCenter: parent.verticalCenter
            width: 30; height: 30; radius: 4
            maskColor: bar.glass
            source: bar.player.current?.art ?? ""
            visible: !!bar.player.current
        }
        Column {
            x: 38; anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: -1
            width: parent.width - 38
            visible: !!bar.player.current
            Text {
                width: parent.width; elide: Text.ElideRight
                text: bar.player.current?.title ?? ""
                color: Theme.label
                font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: Font.DemiBold }
            }
            Text {
                width: parent.width; elide: Text.ElideRight
                text: bar.player.current ? (bar.player.current.radio ? bar.player.current.artist
                     : bar.player.current.artist + " — " + bar.player.current.album) : ""
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
            }
            TapHandler { onTapped: if (bar.player.current && !bar.player.current.radio) bar.openAlbum(bar.player.current) }
        }
        Text {
            anchors.centerIn: parent
            visible: !bar.player.current
            text: "Not Playing"
            color: Theme.secondaryLabel
            font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: Font.Medium }
        }
        // Progress: a hairline under the song; click or drag to seek.
        Item {
            id: progress
            visible: !!bar.player.current && !bar.player.current.radio
            x: 0; width: parent.width; height: 8
            anchors.bottom: parent.bottom; anchors.bottomMargin: 0
            Rectangle { y: 3; width: parent.width; height: 2; radius: 1; color: Theme.dark ? "#33ffffff" : "#1f000000" }
            Rectangle {
                y: 3; height: 2; radius: 1
                width: bar.player.duration > 0 ? parent.width * Math.min(1, bar.player.position / bar.player.duration) : 0
                color: Theme.dark ? "#b3ffffff" : "#8c000000"
            }
            MouseArea {
                anchors { fill: parent; topMargin: -4 }
                onPressed: (m) => bar.player.seek(m.x / width * bar.player.duration)
                onPositionChanged: (m) => { if (pressed) bar.player.seek(Math.max(0, Math.min(1, m.x / width)) * bar.player.duration) }
            }
        }
    }

    Row {
        id: tools
        anchors { right: parent.right; rightMargin: 12 }
        height: parent.height
        Btn { symbol: "list"; onClicked: bar.showQueue() }
        Btn { symbol: bar.player.muted || bar.player.volume === 0 ? "speaker" : "speaker-wave"; onClicked: volumePop.visible = !volumePop.visible }
    }

    // Volume
    Rectangle {
        id: volumePop
        visible: false
        anchors { right: parent.right; bottom: parent.top; bottomMargin: 8 }
        width: 200; height: 36; radius: 18
        color: bar.glass
        border { width: 0.5; color: Theme.dark ? "#26ffffff" : "#1a000000" }
        Symbol { x: 12; anchors.verticalCenter: parent.verticalCenter; name: "speaker"; size: 12 }
        Item {
            id: vol
            x: 32; width: parent.width - 64; height: parent.height
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 4; radius: 2; color: Theme.dark ? "#33ffffff" : "#1f000000" }
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * bar.player.volume; height: 4; radius: 2; color: Theme.dark ? "#ffffff" : "#8c000000" }
            Rectangle {
                x: parent.width * bar.player.volume - 7; anchors.verticalCenter: parent.verticalCenter
                width: 14; height: 14; radius: 7; color: "#ffffff"
                border { width: 0.5; color: "#33000000" }
            }
            MouseArea {
                anchors.fill: parent
                onPressed: (m) => bar.player.volume = Math.max(0, Math.min(1, m.x / width))
                onPositionChanged: (m) => { if (pressed) bar.player.volume = Math.max(0, Math.min(1, m.x / width)) }
            }
        }
        Symbol { anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter } name: "speaker-wave"; size: 13 }
    }
}
