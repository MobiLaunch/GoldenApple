// Quick Look: Space (or ⌘Y) on a selected item previews it without opening an
// app, as Finder does. Pictures are shown whole, text and code are shown as
// text, anything else as its icon with what it is, how big and when it changed.
// The arrow keys keep moving the selection underneath, and the preview follows;
// Space or Escape closes it.
import Quickshell
import Quickshell.Io
import QtQuick
import "../lib"
import "../lib/theme"
import "../lib/paths.js" as Paths

Item {
    id: look
    anchors.fill: parent
    z: 105
    visible: card.opacity > 0
    property bool open: false
    property var entry: null            // the selected item, as files/helper.py lists it
    signal openRequested(var entry)
    signal closed()

    readonly property string kind: {
        if (!entry) return ""
        if (entry.folder) return "folder"
        const mime = entry.mime ?? ""
        if (/^image\/(png|jpeg|gif|webp|bmp|svg\+xml)$/.test(mime)) return "image"
        if (mime.startsWith("text/") || /(json|xml|javascript|x-sh|x-python|yaml|toml)/.test(mime)
            || /\.(md|qml|conf|ini|log|rs|go|c|h|cpp|swift|ts|tsx|jsx|lua|desktop)$/i.test(entry.name ?? ""))
            return (entry.size ?? 0) <= 512 * 1024 ? "text" : "other"
        return "other"
    }
    readonly property string kindLabel: {
        if (!entry) return ""
        if (entry.folder) return "Folder"
        const mime = entry.mime ?? ""
        const ext = /\.([^.]+)$/.exec(entry.name ?? "")
        if (mime === "application/pdf") return "PDF document"
        if (mime.startsWith("image/")) return (ext ? ext[1].toUpperCase() + " " : "") + "image"
        if (mime.startsWith("video/")) return "Movie"
        if (mime.startsWith("audio/")) return "Audio"
        if (mime === "application/zip") return "ZIP archive"
        return ext ? ext[1].toUpperCase() + " document" : "Document"
    }
    function formatSize(bytes) {
        if (bytes < 1000) return bytes + " bytes"
        if (bytes < 1e6) return (bytes / 1e3).toFixed(bytes < 1e4 ? 1 : 0) + " KB"
        if (bytes < 1e9) return (bytes / 1e6).toFixed(1) + " MB"
        return (bytes / 1e9).toFixed(1) + " GB"
    }

    property string textContent: ""
    FileView {
        id: textFile
        path: look.open && look.kind === "text" ? look.entry.path : ""
        printErrors: false
        onPathChanged: look.textContent = ""
        onLoaded: look.textContent = text()
    }

    // A light scrim, so the preview reads as in front; a click on it closes.
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: look.open ? (Theme.dark ? 0.28 : 0.12) : 0
        Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 1 : 155 } }
        MouseArea { anchors.fill: parent; enabled: look.open; onClicked: look.closed() }
    }

    Rectangle {
        id: card
        readonly property real maxW: look.width - 120
        readonly property real maxH: look.height - 110
        // A picture sits this far inside the card, so its square corners stay
        // within the card's rounded ones (in any renderer, no clipping needed).
        readonly property real mat: 6
        // Pictures size the card to themselves; everything else gets a page.
        readonly property size fit: {
            if (look.kind === "image" && picture.status === Image.Ready && picture.implicitWidth > 0) {
                const s = Math.min(1, (maxW - 2 * mat) / picture.implicitWidth, (maxH - bar.height - 2 * mat) / picture.implicitHeight)
                return Qt.size(Math.max(360, picture.implicitWidth * s + 2 * mat), Math.max(240, picture.implicitHeight * s + bar.height + 2 * mat))
            }
            if (look.kind === "text") return Qt.size(Math.min(maxW, 760), maxH)
            return Qt.size(Math.min(maxW, 460), Math.min(maxH, 380))
        }
        width: fit.width; height: fit.height
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 14
        radius: 16
        clip: true
        color: Theme.dark ? "#1e1e20" : "#fafafa"
        border { width: 1; color: Theme.dark ? "#30ffffff" : "#1f000000" }
        opacity: look.open ? 1 : 0
        scale: look.open || Theme.reduceMotion ? 1 : 0.9
        Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 1 : (look.open ? 160 : 140) } }
        Behavior on scale { NumberAnimation { duration: Theme.reduceMotion ? 1 : 210; easing.type: Easing.OutBack; easing.overshoot: 0.9 } }
        Behavior on width { enabled: look.open && !Theme.reduceMotion; NumberAnimation { duration: 155; easing.type: Easing.OutCubic } }
        Behavior on height { enabled: look.open && !Theme.reduceMotion; NumberAnimation { duration: 155; easing.type: Easing.OutCubic } }
        MouseArea { anchors.fill: parent }       // clicks inside don't close it

        Image {
            id: picture
            visible: look.kind === "image"
            anchors { fill: parent; topMargin: bar.height + card.mat; leftMargin: card.mat; rightMargin: card.mat; bottomMargin: card.mat }
            source: look.open && look.kind === "image" ? Paths.fileUrl(look.entry.path) : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            smooth: true
            mipmap: true
        }

        // Title bar: close, the name, and Open.
        Rectangle {
            id: bar
            width: parent.width; height: 44
            color: Theme.dark ? "#0dffffff" : "#08000000"
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.separator }
            ToolbarButton {
                anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                symbol: "xmark"; round: true
                onClicked: look.closed()
                Accessible.name: "Close"
            }
            Column {
                anchors.centerIn: parent
                width: parent.width - 260
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                    text: look.entry?.name ?? ""
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.DemiBold }
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    visible: look.kind === "image" && picture.status === Image.Ready
                    text: picture.implicitWidth + " × " + picture.implicitHeight
                    color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                }
            }
            Button {
                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                text: "Open"
                onClicked: look.openRequested(look.entry)
            }
        }

        Flickable {
            id: textView
            visible: look.kind === "text"
            anchors { fill: parent; topMargin: bar.height + 1 }
            contentHeight: body.implicitHeight + 40
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Text {
                id: body
                x: 22; y: 18
                width: textView.width - 44
                text: look.kind === "text" ? look.textContent : ""
                textFormat: Text.PlainText
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                color: Theme.label
                font { family: /\.(md|txt)$/i.test(look.entry?.name ?? "") ? Theme.fontUi : "SF Mono"; pixelSize: Theme.fs(13) }
                lineHeight: 1.15
            }
        }

        // Anything else: the icon, large, with what it is.
        Column {
            visible: look.kind === "folder" || look.kind === "other"
            anchors { centerIn: parent; verticalCenterOffset: bar.height / 2 }
            spacing: 6
            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 128; height: 128
                source: look.entry ? Quickshell.iconPath(look.entry.icon, look.entry.folder ? "folder" : "text-x-generic") : ""
                sourceSize: Qt.size(256, 256)
                smooth: true; mipmap: true
            }
            Item { width: 1; height: 8 }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: look.entry?.name ?? ""
                color: Theme.label
                font { family: Theme.fontUi; pixelSize: Theme.fs(17); weight: Font.DemiBold }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: look.entry ? look.kindLabel + (look.entry.folder ? "" : " · " + look.formatSize(look.entry.size ?? 0)) : ""
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: look.entry ? "Modified " + new Date(look.entry.modified * 1000).toLocaleString(Qt.locale(), "MMMM d, yyyy 'at' h:mm AP") : ""
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
            }
        }
    }
}
