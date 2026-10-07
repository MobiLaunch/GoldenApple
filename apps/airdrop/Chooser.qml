// Choose files to send: a small open panel over the window, with the usual
// places on the left and the folder's contents on the right. Click to select
// (several at once), double-click a folder to open it, then Send.
import QtQuick
import Qt.labs.folderlistmodel
import "../lib"
import "../lib/theme"

Item {
    id: chooser
    property string to: ""                 // the device's name, for the title
    property var selected: ({})            // path → true
    readonly property var paths: Object.keys(selected)
    property string homePath: ""           // $HOME, from the window
    signal accepted(var paths)
    signal cancelled()
    anchors.fill: parent
    z: 60

    function open(folder) {
        selected = ({})
        files.folder = "file://" + folder
    }
    function toggle(path) {
        const next = Object.assign({}, selected)
        if (next[path]) delete next[path]; else next[path] = true
        selected = next
    }
    function enter(path) { files.folder = "file://" + path }

    Rectangle { anchors.fill: parent; color: "#33000000"; TapHandler { onTapped: chooser.cancelled() } }
    Glass {
        id: panel
        role: "menu"
        anchors.centerIn: parent
        width: Math.min(620, chooser.width - 40)
        height: Math.min(440, chooser.height - 40)
        radius: 22
        TapHandler {}                       // clicks inside stay inside

        Text {
            id: title
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 18 }
            horizontalAlignment: Text.AlignHCenter
            text: "Choose Files to Send to " + chooser.to
            elide: Text.ElideRight
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.Bold }
        }

        // Places.
        Column {
            id: places
            anchors { left: parent.left; top: title.bottom; bottom: buttons.top; margins: 14 }
            width: 140
            spacing: 2
            Repeater {
                model: [
                    { label: "Desktop", dir: "Desktop", icon: "window" },
                    { label: "Documents", dir: "Documents", icon: "doc" },
                    { label: "Downloads", dir: "Downloads", icon: "download" },
                    { label: "Pictures", dir: "Pictures", icon: "photo" },
                    { label: "Music", dir: "Music", icon: "music" },
                    { label: "Movies", dir: "Videos", icon: "film" },
                    { label: "Home", dir: "", icon: "house" }
                ]
                delegate: Rectangle {
                    required property var modelData
                    readonly property string path: chooser.homePath + (modelData.dir ? "/" + modelData.dir : "")
                    readonly property bool current: String(files.folder).replace("file://", "") === path
                    width: places.width; height: 26; radius: 7
                    color: current ? Theme.selection : hover.hovered ? Theme.fill : "transparent"
                    Row {
                        anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                        spacing: 7
                        Symbol { name: modelData.icon; size: 13; tone: "accent"; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            color: Theme.label
                            font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                        }
                    }
                    HoverHandler { id: hover }
                    TapHandler { onTapped: chooser.enter(parent.path) }
                }
            }
        }

        // The folder.
        Rectangle {
            anchors { left: places.right; right: parent.right; top: title.bottom; bottom: buttons.top; margins: 14; leftMargin: 6 }
            radius: 10
            color: Theme.dark ? "#1affffff" : "#ccffffff"
            border { width: 0.5; color: Theme.separator }
            clip: true

            Row {
                id: pathBar
                x: 8; y: 6
                spacing: 6
                Rectangle {
                    width: 22; height: 22; radius: 11
                    color: up.hovered ? Theme.fill : "transparent"
                    Symbol { anchors.centerIn: parent; name: "chevron-left"; size: 11; tone: "auto" }
                    HoverHandler { id: up }
                    TapHandler { onTapped: files.folder = files.parentFolder }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(files.folder).replace("file://", "").replace(chooser.homePath, "~")
                    color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                }
            }
            ListView {
                anchors { left: parent.left; right: parent.right; top: pathBar.bottom; bottom: parent.bottom; topMargin: 6; margins: 4 }
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: FolderListModel {
                    id: files
                    showDirsFirst: true
                    showHidden: false
                    sortCaseSensitive: false
                }
                delegate: Rectangle {
                    required property string fileName
                    required property string filePath
                    required property bool fileIsDir
                    required property var fileSize
                    readonly property bool picked: !!chooser.selected[filePath]
                    width: ListView.view.width
                    height: 26
                    radius: 6
                    color: picked ? Theme.accent : rowHover.hovered ? Theme.fill : "transparent"
                    Row {
                        anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                        spacing: 8
                        Symbol { name: fileIsDir ? "folder" : "doc"; size: 13; tone: picked ? "white" : fileIsDir ? "accent" : "gray"; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            width: 280
                            text: fileName
                            elide: Text.ElideMiddle
                            color: picked ? "#ffffff" : Theme.label
                            font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    Text {
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        visible: !fileIsDir
                        text: fileSize > 1e9 ? (fileSize / 1e9).toFixed(1) + " GB" : fileSize > 1e6 ? (fileSize / 1e6).toFixed(1) + " MB"
                            : fileSize > 1e3 ? Math.round(fileSize / 1e3) + " KB" : fileSize + " bytes"
                        color: picked ? "#ffffff" : Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                    }
                    HoverHandler { id: rowHover }
                    TapHandler { onTapped: chooser.toggle(filePath) }
                    TapHandler { onDoubleTapped: if (fileIsDir) chooser.enter(filePath) }
                }
            }
        }

        Row {
            id: buttons
            anchors { right: parent.right; bottom: parent.bottom; margins: 16 }
            spacing: 8
            Button { text: "Cancel"; onClicked: chooser.cancelled() }
            Button {
                text: chooser.paths.length > 1 ? "Send " + chooser.paths.length + " Items" : "Send"
                prominent: true
                enabled: chooser.paths.length > 0
                onClicked: chooser.accepted(chooser.paths)
            }
        }
    }
    Keys.onEscapePressed: cancelled()
}
