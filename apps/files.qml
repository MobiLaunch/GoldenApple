//@ pragma AppId org.goldengate.Files
// Golden Gate Files: Finder-style native filesystem browser.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "lib"
import "lib/theme"
import "files"
import "lib/paths.js" as Paths

ShellRoot {
    AppWindow {
        id: win
        title: files.title
        onBackRequested: files.goBack()
        onForwardRequested: files.goForward()
        implicitWidth: Math.min(1050, (Quickshell.screens[0]?.width ?? 1280) - 80)
        implicitHeight: Math.min(700, (Quickshell.screens[0]?.height ?? 900) - 130)
        minimumSize: Qt.size(720, 440)
        property bool sidebarShown: true
        sidebarWidth: sidebarShown ? 210 : 0
        fullSizeContent: true
        background: Theme.contentBg

        toolbarSidebar: [
            ToolbarButton { round: true; symbol: "sidebar"; checked: win.sidebarShown; onClicked: win.sidebarShown = !win.sidebarShown }
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

                Button {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: files.inTrash
                    enabled: files.entries.length > 0
                    text: "Empty"
                    onClicked: files.askEmptyTrash()
                }

                ToolbarButton {
                    round: true
                    symbol: "folder"
                    enabled: !files.special
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
                text: "Favorites"
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
                        id: place
                        required property var modelData
                        width: parent.width
                        text: modelData.name
                        symbol: modelData.icon
                        selected: files.path === modelData.path || placeDrop.containsDrag
                        onClicked: files.navigate(modelData.path)
                        // Drop on a place to move there; on the Trash to throw away.
                        DropArea {
                            id: placeDrop
                            anchors.fill: parent
                            enabled: place.modelData.path !== "recents:"
                            onEntered: (drag) => drag.accepted = place.modelData.path === "trash:"
                                ? files.pathsOf(drag.urls).length > 0 && !files.inTrash
                                : files.accepts(drag, place.modelData.path)
                            onDropped: (drop) => files.dropOn(drop, place.modelData.path)
                        }
                    }
                }
            }
        ]

        FocusScope {
            id: files
            anchors.fill: parent
            focus: true

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

            // Two views that aren't folders: Recents and the Trash.
            readonly property bool inTrash: path === "trash:"
            readonly property bool inRecents: path === "recents:"
            readonly property bool special: inTrash || inRecents

            readonly property string title: {
                if (inTrash) return "Trash"
                if (inRecents) return "Recents"
                if (path === home) return "Home"
                const bits = path.split("/").filter((x) => x)
                return bits.length ? bits[bits.length - 1] : "Computer"
            }

            readonly property var locations: [
                { name: "Recents", icon: "clock", path: "recents:" },
                { name: "Home", icon: "house", path: home },
                { name: "Desktop", icon: "rectangle-fill", path: home + "/Desktop" },
                { name: "Documents", icon: "doc", path: home + "/Documents" },
                { name: "Downloads", icon: "download", path: home + "/Downloads" },
                { name: "Pictures", icon: "photo", path: home + "/Pictures" },
                { name: "Music", icon: "music", path: home + "/Music" },
                { name: "Videos", icon: "film", path: home + "/Videos" },
                { name: "Trash", icon: "trash", path: "trash:" }
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
                files.forceActiveFocus()
            }

            // The keyboard, as in Finder: arrows move the selection (by rows in
            // the grid), Space or ⌘Y is Quick Look, Return renames, ⌘O or ⌘↓
            // opens, ⌘↑ goes to the enclosing folder, ⌘⌫ moves to the Trash.
            // (keyd sends ⌘ shortcuts as Ctrl, and ⌘↑ ⌘↓ as Ctrl+Home/End.)
            readonly property int selectedIndex: entries.findIndex((e) => e.path === selectedPath)
            readonly property var selectedEntry: selectedIndex >= 0 ? entries[selectedIndex] : null
            function moveSelection(step) {
                if (!entries.length) return
                const i = selectedIndex < 0 ? 0 : Math.max(0, Math.min(entries.length - 1, selectedIndex + step))
                select(entries[i])
                if (view === "grid") grid.positionViewAtIndex(i, GridView.Contain)
                else list.positionViewAtIndex(i, ListView.Contain)
            }
            function rename() {
                if (!selectedEntry) return
                dialogMode = "rename"
                dialogText = selectedName
                editDialog.visible = true
                Qt.callLater(() => dialogField.input.forceActiveFocus())
            }
            function enclosingFolder() {
                if (special) return
                const up = path.replace(/\/[^/]+\/?$/, "") || "/"
                if (up !== path) navigate(up)
            }
            Keys.onPressed: (event) => {
                const ctrl = event.modifiers & Qt.ControlModifier
                const columns = view === "grid" ? Math.max(1, Math.floor(grid.width / grid.cellWidth)) : 1
                if (event.key === Qt.Key_Space || (ctrl && event.key === Qt.Key_Y)) {
                    if (selectedEntry || quickLook.open) quickLook.open = !quickLook.open
                } else if (event.key === Qt.Key_Escape && quickLook.open) quickLook.open = false
                else if (ctrl && (event.key === Qt.Key_O || event.key === Qt.Key_End)) {
                    if (selectedEntry) { quickLook.open = false; openEntry(selectedEntry) }
                } else if (ctrl && event.key === Qt.Key_Home) enclosingFolder()
                else if (ctrl && event.key === Qt.Key_Backspace) {
                    if (selectedEntry && !inTrash) runOperation(["trash", selectedPath], "trash")
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (!quickLook.open) rename()
                } else if (event.key === Qt.Key_Left && view === "grid") moveSelection(-1)
                else if (event.key === Qt.Key_Right && view === "grid") moveSelection(1)
                else if (event.key === Qt.Key_Up) moveSelection(-columns)
                else if (event.key === Qt.Key_Down) moveSelection(columns)
                else return
                event.accepted = true
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

            // ---------------------------------------------------- Trash
            function putBack(entry) { if (entry?.trashName) runOperation(["put-back", entry.trashName], "put-back") }
            function askEmptyTrash() { confirmEmpty.visible = true }
            // An item in Recents, shown where it lives.
            function showInFolder(entry) {
                initialSelect = entry.path
                navigate(entry.path.replace(/\/[^/]+$/, "") || "/")
            }

            // ---------------------------------------------------- drag and drop
            // Dropped on a folder (or on the window: this folder), items move
            // when they come from Files on the same disk and are copied from
            // another disk or another app; on the Trash they go to the Trash.
            function pathsOf(urls) {
                return Array.from(urls ?? []).map((u) => String(u)).filter((u) => u.startsWith("file://"))
                    .map((u) => decodeURIComponent(u.slice(7)))
            }
            function accepts(drag, dest) {
                const paths = pathsOf(drag.urls)
                // Not onto itself, and not a folder into its own contents.
                return paths.length > 0 && !paths.some((p) => dest === p || dest.startsWith(p + "/"))
            }
            function dropOn(drop, dest) {
                const paths = pathsOf(drop.urls)
                if (!paths.length) return
                const ours = drop.source !== null && drop.source !== undefined
                if (dest === "trash:") {
                    runOperation(["trash"].concat(paths), "trash")
                    drop.accept(Qt.MoveAction)
                    return
                }
                const copy = !ours || drop.proposedAction === Qt.CopyAction
                runOperation(["drop", dest, copy ? "copy" : "auto"].concat(paths), "drop")
                drop.accept(copy ? Qt.CopyAction : Qt.MoveAction)
            }

            // An item's menu (right-click), for where it is.
            function itemMenu(anchor, x, y, entry) {
                select(entry)
                const items = inTrash ? [
                    { text: "Put Back", action: () => putBack(entry) },
                    { text: "Quick Look", shortcut: "Space", action: () => quickLook.open = true },
                    { separator: true },
                    { text: "Empty Trash", destructive: true, action: () => askEmptyTrash() }
                ] : [
                    { text: "Open", action: () => openEntry(entry) },
                    { text: "Quick Look", shortcut: "Space", action: () => quickLook.open = true }
                ].concat(inRecents ? [{ text: "Show in Enclosing Folder", action: () => showInFolder(entry) }] : [], [
                    { text: "Rename", action: () => rename() },
                    { text: "Share with AirDrop…", action: () => Quickshell.execDetached(["gg-airdrop", entry.path]) },
                    { separator: true },
                    { text: "Move to Trash", action: () => runOperation(["trash", entry.path], "trash") }
                ])
                menu.popup(anchor, x, y, items)
            }

            function openActions(anchor) {
                if (inTrash) {
                    menu.popup(anchor, 0, anchor.height + 6, [
                        { text: "Put Back", enabled: !!selectedEntry, action: () => putBack(selectedEntry) },
                        { text: "Quick Look", shortcut: "Space", enabled: !!selectedPath, action: () => quickLook.open = true },
                        { separator: true },
                        { text: "Empty Trash", destructive: true, enabled: entries.length > 0, action: () => askEmptyTrash() }
                    ])
                    return
                }
                const actions = [
                    { text: "New Folder", enabled: !special, action: () => {
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
                    { text: "Quick Look", shortcut: "Space", enabled: !!selectedPath, action: () => quickLook.open = true },
                    { text: "Rename", enabled: !!selectedPath, action: () => rename() },
                    { text: "Show in Enclosing Folder", enabled: inRecents && !!selectedEntry, action: () => showInFolder(selectedEntry) },
                    { text: "Share with AirDrop…", enabled: !!selectedPath, action: () => Quickshell.execDetached(["gg-airdrop", selectedPath]) },
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
                visible: files.special && !files.loading && !files.error && files.entries.length === 0
                anchors.centerIn: parent
                width: Math.min(420, parent.width - 40)
                height: 220
                symbol: files.inTrash ? "trash" : "clock"
                title: files.inTrash ? "Trash Is Empty" : "No Recent Files"
                text: files.inTrash ? "Items you move to the Trash stay here until you empty it."
                    : "Files you open or change show up here."
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

            // What an item hands over when it's dragged: its file, to a folder,
            // the sidebar, the Trash or another app. (Nothing leaves the Trash
            // by dragging; Put Back does that.)
            component DragSource: Item {
                id: source
                property var entry
                property MouseArea area
                width: 1; height: 1
                Drag.active: !!area && area.drag.active && !files.inTrash
                Drag.dragType: Drag.Automatic
                Drag.supportedActions: Qt.MoveAction | Qt.CopyAction
                Drag.proposedAction: Qt.MoveAction
                Drag.mimeData: ({ "text/uri-list": Paths.fileUrl(entry?.path ?? "") + "\r\n" })
                Drag.imageSource: Quickshell.iconPath(entry?.icon ?? "", entry?.folder ? "folder" : "text-x-generic")
                Drag.imageSourceSize: Qt.size(64, 64)
                Drag.onDragFinished: { source.x = 0; source.y = 0; files.reload() }
            }

            // Dropped on the window, not on a folder: into this folder.
            DropArea {
                anchors.fill: parent
                enabled: !files.special
                onEntered: (drag) => drag.accepted = files.accepts(drag, files.path)
                onDropped: (drop) => files.dropOn(drop, files.path)
            }

            GridView {
                id: grid
                visible: files.view === "grid" && !files.loading && !files.error
                // The window draws under its toolbar; the grid starts below it and
                // scrolls up under it (clipped at the window, not at the toolbar).
                anchors { fill: parent; margins: 18; topMargin: 0 }
                topMargin: win.toolbarHeight + 10
                cellWidth: 118
                cellHeight: 112
                model: files.entries

                delegate: Item {
                    id: cell
                    required property var modelData
                    width: grid.cellWidth
                    height: grid.cellHeight
                    readonly property bool selected: files.selectedPath === modelData.path || cellDrop.containsDrag

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
                    DragSource { id: cellDrag; entry: cell.modelData; area: cellArea }
                    MouseArea {
                        id: cellArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        drag.target: files.inTrash ? null : cellDrag
                        drag.threshold: 6
                        onPressed: (mouse) => { if (mouse.button === Qt.LeftButton) files.select(cell.modelData) }
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.RightButton) files.itemMenu(cell, mouse.x, mouse.y, cell.modelData)
                            else files.select(cell.modelData)
                        }
                        onDoubleClicked: files.openEntry(cell.modelData)
                    }
                    // A folder takes what's dropped on it.
                    DropArea {
                        id: cellDrop
                        anchors.fill: parent
                        enabled: cell.modelData.folder && !files.special
                        onEntered: (drag) => drag.accepted = files.accepts(drag, cell.modelData.path)
                        onDropped: (drop) => files.dropOn(drop, cell.modelData.path)
                    }
                }
            }

            ListView {
                id: list
                visible: files.view === "list" && !files.loading && !files.error
                anchors { fill: parent; margins: 16; topMargin: 0 }
                topMargin: win.toolbarHeight + 6
                spacing: 1
                model: files.entries

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    width: list.width
                    height: 36
                    radius: 7
                    readonly property bool selected: files.selectedPath === modelData.path || rowDrop.containsDrag
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
                        text: files.inTrash && row.modelData.origin
                            ? row.modelData.origin.replace(/\/[^/]+$/, "").replace(files.home, "~")
                            : new Date(row.modelData.modified * 1000).toLocaleDateString(Qt.locale(), Locale.ShortFormat)
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
                    DragSource { id: rowDrag; entry: row.modelData; area: rowArea }
                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        drag.target: files.inTrash ? null : rowDrag
                        drag.threshold: 6
                        onPressed: (mouse) => { if (mouse.button === Qt.LeftButton) files.select(row.modelData) }
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.RightButton) files.itemMenu(row, mouse.x, mouse.y, row.modelData)
                            else files.select(row.modelData)
                        }
                        onDoubleClicked: files.openEntry(row.modelData)
                    }
                    DropArea {
                        id: rowDrop
                        anchors.fill: parent
                        enabled: row.modelData.folder && !files.special
                        onEntered: (drag) => drag.accepted = files.accepts(drag, row.modelData.path)
                        onDropped: (drop) => files.dropOn(drop, row.modelData.path)
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

            // Empty Trash asks first, as on the Mac.
            Glass {
                id: confirmEmpty
                parent: win.overlay
                visible: false
                anchors.centerIn: parent
                width: 300
                height: confirmColumn.implicitHeight + 40
                radius: 22
                tint: Theme.glassRegular.tint
                z: 110
                onVisibleChanged: if (visible) emptyButton.forceActiveFocus(); else files.forceActiveFocus()
                Keys.onEscapePressed: visible = false
                Column {
                    id: confirmColumn
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
                    spacing: 10
                    Symbol { anchors.horizontalCenter: parent.horizontalCenter; name: "trash"; size: 34; tone: "auto" }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: "Are you sure you want to permanently erase the items in the Trash?"
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: 13; weight: Font.Bold }
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: "You can’t undo this action."
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: 11 }
                    }
                    Item { width: 1; height: 4 }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8
                        Button { width: 122; text: "Cancel"; onClicked: confirmEmpty.visible = false }
                        Button {
                            id: emptyButton
                            width: 122
                            text: "Empty Trash"
                            prominent: true
                            destructive: true
                            onClicked: { confirmEmpty.visible = false; files.runOperation(["empty-trash"], "empty-trash") }
                        }
                    }
                }
            }

            QuickLook {
                id: quickLook
                parent: win.overlay
                entry: files.selectedEntry
                onOpenRequested: (entry) => { open = false; files.openEntry(entry) }
                onClosed: open = false
                onOpenChanged: if (!open) files.forceActiveFocus()
                // Nothing selected (a folder changed, the item went to the Trash):
                // nothing to show. GG_FILES_QUICKLOOK=1 with GG_FILES_SELECT opens
                // it on that item, for screenshots.
                property bool openOnSelect: Quickshell.env("GG_FILES_QUICKLOOK") === "1"
                onEntryChanged: {
                    if (!entry) open = false
                    else if (openOnSelect) { openOnSelect = false; open = true }
                }
            }

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
                onVisibleChanged: if (!visible) files.forceActiveFocus()

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
