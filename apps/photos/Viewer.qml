// One photo or video, fitted to the window, with arrows at the sides on hover,
// click-to-play for videos, and an info panel (name, size, dimensions, place).
import Quickshell
import QtQuick
import QtMultimedia
import "../lib"
import "../lib/theme"

Item {
    id: viewer
    property var item: null
    property bool canPrevious: false
    property bool canNext: false
    property bool infoOpen: false
    signal previous()
    signal next()

    readonly property bool isVideo: item?.kind === "video"
    onItemChanged: { video.stop(); if (isVideo) video.play() }
    onVisibleChanged: if (!visible) video.stop()

    Image {
        id: photo
        anchors { fill: parent; margins: 16; rightMargin: viewer.infoOpen ? 290 : 16 }
        visible: !viewer.isVideo
        source: viewer.item && !viewer.isVideo ? "file://" + viewer.item.path : ""
        sourceSize: Qt.size(Math.ceil(width * 2), Math.ceil(height * 2))
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        autoTransform: true
        smooth: true; mipmap: true
        // The previous one stays until the next has loaded (no flash of empty).
        Image {
            id: previousPhoto
            property url lastSource
            anchors.fill: parent
            visible: photo.status === Image.Loading
            source: photo.status === Image.Loading ? lastSource : ""
            fillMode: Image.PreserveAspectFit
            Connections { target: photo; function onStatusChanged() { if (photo.status === Image.Ready) previousPhoto.lastSource = photo.source } }
        }
    }

    Video {
        id: video
        anchors { fill: parent; margins: 16; rightMargin: viewer.infoOpen ? 290 : 16 }
        visible: viewer.isVideo
        source: viewer.item && viewer.isVideo ? "file://" + viewer.item.path : ""
        fillMode: VideoOutput.PreserveAspectFit
        loops: MediaPlayer.Infinite
        TapHandler { onTapped: video.playbackState === MediaPlayer.PlayingState ? video.pause() : video.play() }
        Rectangle {
            anchors.centerIn: parent
            width: 64; height: 64; radius: 32
            visible: video.playbackState !== MediaPlayer.PlayingState
            color: "#80000000"
            Symbol { anchors.centerIn: parent; anchors.horizontalCenterOffset: 2; name: "play"; tone: "white"; size: 26 }
        }
        // Scrubber
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 24 }
            height: 6; radius: 3
            color: "#59000000"
            visible: video.duration > 0
            Rectangle { width: parent.width * video.position / Math.max(1, video.duration); height: parent.height; radius: 3; color: "#e6ffffff" }
            MouseArea {
                anchors { fill: parent; margins: -8 }
                onPressed: (m) => video.seek(Math.max(0, Math.min(1, (m.x - 8) / (width - 16))) * video.duration)
            }
        }
    }

    // Previous / next on hover
    HoverHandler { id: hover }
    component Arrow: Rectangle {
        id: arrow
        property string symbol
        signal clicked()
        width: 36; height: 36; radius: 18
        color: Theme.dark ? "#cc3a3a3e" : "#d9ffffff"
        border { width: 0.5; color: Theme.dark ? "#33ffffff" : "#1f000000" }
        Symbol { anchors.centerIn: parent; name: arrow.symbol; size: 15 }
        MouseArea { anchors.fill: parent; onClicked: arrow.clicked() }
    }
    Arrow {
        anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter }
        visible: hover.hovered && viewer.canPrevious
        symbol: "chevron-left"
        onClicked: viewer.previous()
    }
    Arrow {
        anchors { right: parent.right; rightMargin: viewer.infoOpen ? 294 : 20; verticalCenter: parent.verticalCenter }
        visible: hover.hovered && viewer.canNext
        symbol: "chevron-right"
        onClicked: viewer.next()
    }

    // Info
    Rectangle {
        visible: viewer.infoOpen && !!viewer.item
        anchors { right: parent.right; top: parent.top; bottom: parent.bottom; margins: 8 }
        width: 270; radius: 16
        color: Theme.dark ? "#f22a2a2d" : "#f7fbfbfd"
        border { width: 0.5; color: Theme.dark ? "#26ffffff" : "#1f000000" }
        Column {
            x: 16; y: 16; width: parent.width - 32
            spacing: 12
            Text {
                width: parent.width; elide: Text.ElideMiddle
                text: viewer.item?.name ?? ""
                color: Theme.label
                font { family: Theme.fontUi; pixelSize: 15; weight: Font.Bold }
            }
            Repeater {
                model: [
                    ["Date", viewer.item ? new Date(viewer.item.mtime * 1000).toLocaleString(Qt.locale(), "dddd d MMMM yyyy 'at' " + Qt.locale().timeFormat(Locale.ShortFormat)) : ""],
                    ["Dimensions", viewer.isVideo ? (video.metaData.value(MediaMetaData.Resolution) ? video.metaData.value(MediaMetaData.Resolution).width + " × " + video.metaData.value(MediaMetaData.Resolution).height : "")
                                                  : info.w ? info.w + " × " + info.h : ""],
                    ["Length", viewer.isVideo ? Math.floor(viewer.item.seconds / 60) + ":" + String(viewer.item.seconds % 60).padStart(2, "0") : ""],
                    ["Folder", viewer.item ? viewer.item.path.replace(/\/[^/]+$/, "").replace(Quickshell.env("HOME"), "~") : ""],
                ].filter((r) => r[1])
                delegate: Column {
                    required property var modelData
                    width: parent.width
                    Text { text: modelData[0]; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 11; weight: Font.DemiBold } }
                    Text { width: parent.width; wrapMode: Text.Wrap; text: modelData[1]; color: Theme.label; font { family: Theme.fontUi; pixelSize: 13 } }
                }
            }
        }
    }
    // The photo's full size, read without decoding it at full size for display.
    Image {
        id: info
        visible: false
        readonly property int w: implicitWidth
        readonly property int h: implicitHeight
        source: viewer.infoOpen && viewer.item && !viewer.isVideo ? "file://" + viewer.item.path : ""
        asynchronous: true
        autoTransform: true
    }
}
