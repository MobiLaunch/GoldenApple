//@ pragma AppId org.goldengate.Files
// Golden Gate Files: Finder-style native filesystem browser.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "lib"
import "lib/theme"

ShellRoot {
    AppWindow {
        id: win
        title: files.title
        implicitWidth: Math.min(1050, (Quickshell.screens[0]?.width ?? 1280) - 80)
        implicitHeight: Math.min(700, (Quickshell.screens[0]?.height ?? 900) - 130)
        minimumSize: Qt.size(720, 440)
        sidebarWidth: 210
        fullSizeContent: true
        background: Theme.contentBg

        toolbarSidebar: [
            ToolbarButton { round: true; symbol: "sidebar"; checked: true }
        ]

        toolbarItems: [
            Row {
                x: win.contentX + 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                ToolbarPill {
                    ToolbarButton {
                        symbol: "chevron-left"
                        enabled: files.back.length > 0
                        onClicked: files.goBack()
                    }
                    ToolbarButton {
                        symbol: "chevron-right"
                        enabled: files.forward.length > 0
                        onClicked: files.goForward()
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: files.title
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: 13; weight: Font.Bold }
                    }
                    Text {
                        text: files.entries.length + (files.entries.length === 1 ? " item" : " items")
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: 10 }
                    }
                }
            },
            Row {
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 8

                ToolbarPill {
                    ToolbarButton {
                        symbol: "grid"
                        checked: files.view === "grid"
                        onClicked: files.view = "grid"
                    }
                    ToolbarButton {
                        symbol: "list"
                        checked: files.view === "list"
                        onClicked: files.view = "list"
                    }
                }

                ToolbarButton {
                    round: true
                    symbol: "folder"
                    onClicked: {
                        files.dialogMode = "new"
                        files.dialogText = "untitled folder"
                        editDialog.visible = true
                        Qt.callLater(() => dialogField.input.forceActiveFocus())
                    }
                }

                ToolbarButton {
                    id: moreButton
                    round: true
                    symbol: "ellipsis"
                    onClicked: files.openActions(moreButton)
                }

                TextField {
                    id: toolbarSearch
                    width: 190
                    height: 30
                    search: true
                    placeholder: "Search"
                    text: files.query
                    onTextChanged: {
                        files.query = text
                        searchDelay.restart()
                    }
                    input.Keys.onEscapePressed: { text = ""; files.query = ""; files.reload() }
                }
            }
        ]

        sidebar: [
            Text {
                width: parent.width - 12
                x: 8
                text: "Favourites"
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: 11; weight: Font.DemiBold }
            },
            Column {
                y: 24
                width: parent.width
                spacing: 2

                Repeater {
                    model: files.locations
                    delegate: SidebarRow {
                        required property var modelData
                        width: parent.width
                        text: modelData.name
                        symbol: modelData.icon
                        selected: files.path === modelData.path
                        onClicked: files.navigate(modelData.path)
                    }
                }
            }
        ]

        Item {
            id: files
            anchors.fill: parent

            readonly property string helper: Qt.resolvedUrl("files/helper.py").toString().replace("file://", "")
            readonly property string home: Quickshell.env("HOME")
            property string path: Quickshell.env("GG_FILES_PATH") || home
            property string initialSelect: Quickshell.env("GG_FILES_SELECT") || ""
            property var entries: []
            property var back: []
            property var forward: []
            property string selectedPath: ""
            property string selectedName: ""
            property bool selectedFolder: false
            property string view: "grid"
            property string query: ""
            property bool loading: false
            property string error: ""
            property string dialogMode: ""
            property string dialogText: ""
            property string pendingOp: ""

            readonly property string title: {
                if (path === home) return "Home"
                const bits = path.split("/").filter((x) => x)
                return bits.length ? bits[bits.length - 1] : "Computer"
            }

            readonly property var locations: [
                { name: "Home", icon: "house", path: home },
                { name: "Desktop", icon: "rectangle-fill", path: home + "/Desktop" },
                { name: "Documents", icon: "doc", path: home + "/Documents" },
                { name: "Downloads", icon: "download", path: home + "/Downloads" },
                { name: "Pictures", icon: "photo", path: home + "/Pictures" },
                { name: "Music", icon: "music", path: home + "/Music" },
                { name: "Videos", icon: "film", path: home + "/Videos" }
            ]

            function reload() {
                if (listProc.running)
                    return
                loading = true
                error = ""
                listProc.command = ["python3", helper, "list", path, query]
                listProc.running = true
            }

            function navigate(next, record) {
                if (!next || next === path) {
                    reload()
                    return
                }
                if (record !== false) {
                    back = back.concat([path])
                    forward = []
                }
                path = next
                selectedPath = ""
                selectedName = ""
                selectedFolder = false
                query = ""
                toolbarSearch.text = ""
                reload()
            }

            function goBack() {
                if (!back.length)
                    return
                const next = back[back.length - 1]
                back = back.slice(0, -1)
                forward = forward.concat([path])
                path = next
                query = ""
                toolbarSearch.text = ""
                reload()
            }

            function goForward() {
                if (!forward.length)
                    return
                const next = forward[forward.length - 1]
                forward = forward.slice(0, -1)
                back = back.concat([path])
                path = next
                query = ""
                toolbarSearch.text = ""
                reload()
            }

            function select(entry) {
                selectedPath = entry.path
                selectedName = entry.name
                selectedFolder = entry.folder
            }

            function openEntry(entry) {
                if (entry.folder) {
                    navigate(entry.path)
                } else {
                    opProc.command = ["python3", helper, "open", entry.path]
                    pendingOp = "open"
                    opProc.running = true
                }
            }

            function runOperation(args, kind) {
                if (opProc.running)
                    return
                pendingOp = kind
                error = ""
                opProc.command = ["python3", helper].concat(args)
                opProc.running = true
            }

            function openActions(anchor) {
                const actions = [
                    { text: "New Folder", action: () => {
                        dialogMode = "new"
                        dialogText = "untitled folder"
                        editDialog.visible = true
                        Qt.callLater(() => dialogField.input.forceActiveFocus())
                    }},
                    { separator: true },
                    { text: "Open", enabled: !!selectedPath, action: () => {
                        const item = entries.find((e) => e.path === selectedPath)
                        if (item) openEntry(item)
                    }},
                    { text: "Rename", enabled: !!selectedPath, action: () => {
                        dialogMode = "rename"
                        dialogText = selectedName
                        editDialog.visible = true
                        Qt.callLater(() => dialogField.input.forceActiveFocus())
                    }},
                    { text: "Move to Trash", enabled: !!selectedPath, action: () => runOperation(["trash", selectedPath], "trash") },
                    { separator: true },
                    { text: "Refresh", action: () => reload() }
                ]
                menu.popup(anchor, 0, anchor.height + 6, actions)
            }

            function submitDialog() {
                const name = dialogField.text.trim()
                if (!name)
                    return
                if (dialogMode === "new")
                    runOperation(["mkdir", path, name], "mkdir")
                else if (dialogMode === "rename" && selectedPath)
                    runOperation(["rename", selectedPath, name], "rename")
                editDialog.visible = false
            }

            Component.onCompleted: reload()

            Timer {
                id: searchDelay
                interval: 170
                onTriggered: files.reload()
            }

            Process {
                id: listProc
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const r = JSON.parse(text)
                            if (r.ok) {
                                files.path = r.path
                                files.entries = r.entries ?? []
                                files.error = ""
                                if (files.initialSelect) {
                                    const found = files.entries.find((e) => e.path === files.initialSelect)
                                    if (found) files.select(found)
                                    files.initialSelect = ""
                                }
                            } else {
                                files.error = r.error ?? "This folder could not be opened."
                            }
                        } catch (e) {
                            files.error = "Files could not read this folder."
                        }
                    }
                }
                onExited: files.loading = false
            }

            Process {
                id: opProc
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const r = JSON.parse(text)
                            if (!r.ok)
                                files.error = r.error ?? "The operation could not be completed."
                            else if (files.pendingOp !== "open") {
                                files.selectedPath = ""
                                files.reload()
                            }
                        } catch (e) {
                            files.error = "The operation could not be completed."
                        }
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.contentBg
            }

            EmptyState {
                visible: files.loading
                anchors.centerIn: parent
                width: Math.min(420, parent.width - 40)
                height: 220
                symbol: "folder"
                title: "Loading"
                text: "Reading " + files.title + "…"
            }

            ProgressBar {
                visible: files.loading
                anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter; verticalCenterOffset: 72 }
                width: 220
                indeterminate: true
            }

            EmptyState {
                visible: !!files.error && !files.loading
                anchors.centerIn: parent
                width: Math.min(460, parent.width - 40)
                height: 260
                symbol: "info"
                title: "Folder Unavailable"
                text: files.error
            }

            GridView {
                id: grid
                visible: files.view === "grid" && !files.loading && !files.error
                anchors { fill: parent; margins: 18; topMargin: 16 }
                clip: true
                cellWidth: 118
                cellHeight: 112
                model: files.entries

                delegate: Item {
                    id: cell
                    required property var modelData
                    width: grid.cellWidth
                    height: grid.cellHeight
                    readonly property bool selected: files.selectedPath === modelData.path

                    Rectangle {
                        anchors { fill: parent; margins: 4 }
                        radius: 10
                        color: cell.selected
                            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                            : cellHover.hovered
                                ? (Theme.dark ? "#0dffffff" : "#07000000")
                                : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.reduceMotion ? 1 : 80 } }
                    }

                    Column {
                        anchors.centerIn: parent
                        width: parent.width - 8
                        spacing: 5

                        Image {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 62
                            height: 62
                            source: Quickshell.iconPath(modelData.icon, modelData.folder ? "folder" : "text-x-generic")
                            sourceSize: Qt.size(124, 124)
                            smooth: true
                            mipmap: true
                            scale: !Theme.reduceMotion && cellArea.pressed ? 0.95 : 1
                            Behavior on scale { NumberAnimation { duration: Theme.reduceMotion ? 1 : 70; easing.type: Easing.OutCubic } }
                        }

                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            maximumLineCount: 2
                            wrapMode: Text.Wrap
                            elide: Text.ElideRight
                            text: modelData.name
                            color: Theme.label
                            font { family: Theme.fontUi; pixelSize: 12; weight: cell.selected ? Font.DemiBold : Font.Normal }
                        }
                    }

                    HoverHandler { id: cellHover }
                    MouseArea {
                        id: cellArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: (mouse) => {
                            files.select(cell.modelData)
                            if (mouse.button === Qt.RightButton)
                                menu.popup(cell, mouse.x, mouse.y, [
                                    { text: "Open", action: () => files.openEntry(cell.modelData) },
                                    { text: "Rename", action: () => {
                                        files.dialogMode = "rename"
                                        files.dialogText = cell.modelData.name
                                        editDialog.visible = true
                                        Qt.callLater(() => dialogField.input.forceActiveFocus())
                                    }},
                                    { separator: true },
                                    { text: "Move to Trash", action: () => files.runOperation(["trash", cell.modelData.path], "trash") }
                                ])
                        }
                        onDoubleClicked: files.openEntry(cell.modelData)
                    }
                }
            }

            ListView {
                id: list
                visible: files.view === "list" && !files.loading && !files.error
                anchors { fill: parent; margins: 16; topMargin: 12 }
                clip: true
                spacing: 1
                model: files.entries

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    width: list.width
                    height: 36
                    radius: 7
                    readonly property bool selected: files.selectedPath === modelData.path
                    color: selected
                        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                        : rowHover.hovered
                            ? (Theme.dark ? "#0dffffff" : "#07000000")
                            : "transparent"

                    Image {
                        x: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22
                        height: 22
                        source: Quickshell.iconPath(row.modelData.icon, row.modelData.folder ? "folder" : "text-x-generic")
                        sourceSize: Qt.size(44, 44)
                    }

                    Text {
                        x: 40
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width * 0.48
                        text: row.modelData.name
                        elide: Text.ElideRight
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: 12; weight: row.selected ? Font.DemiBold : Font.Normal }
                    }

                    Text {
                        anchors { right: sizeText.left; rightMargin: 24; verticalCenter: parent.verticalCenter }
                        text: new Date(row.modelData.modified * 1000).toLocaleDateString(Qt.locale(), Locale.ShortFormat)
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: 11 }
                    }

                    Text {
                        id: sizeText
                        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        width: 76
                        horizontalAlignment: Text.AlignRight
                        text: row.modelData.folder ? "Folder" : files.formatSize(row.modelData.size)
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: 11 }
                    }

                    HoverHandler { id: rowHover }
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: (mouse) => {
                            files.select(row.modelData)
                            if (mouse.button === Qt.RightButton)
                                files.openActions(row)
                        }
                        onDoubleClicked: files.openEntry(row.modelData)
                    }
                }
            }

            function formatSize(bytes) {
                if (bytes < 1024) return bytes + " B"
                if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB"
                if (bytes < 1024 * 1024 * 1024) return (bytes / 1024 / 1024).toFixed(1) + " MB"
                return (bytes / 1024 / 1024 / 1024).toFixed(1) + " GB"
            }

            PopupMenu { id: menu; parent: win.overlay }

            Glass {
                id: editDialog
                parent: win.overlay
                visible: false
                anchors.centerIn: parent
                width: 380
                height: 150
                radius: 22
                tint: Theme.glassRegular.tint
                z: 110

                Column {
                    anchors { fill: parent; margins: 18 }
                    spacing: 12

                    Text {
                        text: files.dialogMode === "rename" ? "Rename" : "New Folder"
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: 17; weight: Font.DemiBold }
                    }

                    TextField {
                        id: dialogField
                        width: parent.width
                        text: files.dialogText
                        placeholder: "Name"
                        onAccepted: files.submitDialog()
                        input.Keys.onEscapePressed: editDialog.visible = false
                    }

                    Row {
                        anchors.right: parent.right
                        spacing: 8
                        Button { text: "Cancel"; onClicked: editDialog.visible = false }
                        Button {
                            text: files.dialogMode === "rename" ? "Rename" : "Create"
                            prominent: true
                            onClicked: files.submitDialog()
                        }
                    }
                }
            }
        }
    }
}
