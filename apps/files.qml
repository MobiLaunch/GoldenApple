//@ pragma AppId org.goldengate.Files
// CitronOS Files: Finder-style native filesystem browser.
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

                // Locations: the disks, as on a Mac. The system's volume, Home if
                // it has its own, and every other volume you can open; a volume
                // that isn't mounted yet is mounted when it's opened. External
                // ones have an eject button.
                Item { width: 1; height: 12; visible: files.volumes.length > 0 }
                Text {
                    x: 8
                    visible: files.volumes.length > 0
                    text: "Locations"
                    color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: 11; weight: Font.DemiBold }
                }
                Item { width: 1; height: 4; visible: files.volumes.length > 0 }
                Repeater {
                    model: files.volumes
                    delegate: SidebarRow {
                        id: volumeRow
                        required property var modelData
                        objectName: "filesVolume:" + modelData.name
                        width: parent.width
                        text: modelData.name
                        symbol: "drive"
                        opacity: modelData.mounted ? 1 : 0.55
                        selected: !!modelData.mountpoint && files.path === modelData.mountpoint || volumeDrop.containsDrag
                        onClicked: files.openVolume(modelData)
                        DropArea {
                            id: volumeDrop
                            anchors.fill: parent
                            enabled: volumeRow.modelData.mounted && !volumeRow.modelData.readonly
                            onEntered: (drag) => drag.accepted = files.accepts(drag, volumeRow.modelData.mountpoint)
                            onDropped: (drop) => files.dropOn(drop, volumeRow.modelData.mountpoint)
                        }
                        Item {
                            visible: volumeRow.modelData.removable && volumeRow.modelData.mounted
                            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            width: 20; height: 20
                            Rectangle {
                                anchors.fill: parent; radius: 10
                                color: ejectArea.containsMouse ? (Theme.dark ? "#1affffff" : "#12000000") : "transparent"
                            }
                            Symbol { anchors.centerIn: parent; name: "eject"; size: 11; tone: "gray" }
                            MouseArea {
                                id: ejectArea
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: files.eject(volumeRow.modelData)
                            }
                            Accessible.role: Accessible.Button
                            Accessible.name: "Eject " + volumeRow.modelData.name
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
            property bool showHidden: false
            property real free: -1              // space left on this folder's disk
            property string notice: ""          // a passing word in the path bar (an eject that failed)

            // ---------------------------------------------------- disks
            readonly property string disksHelper: Qt.resolvedUrl("lib/disks/disks.py").toString().replace("file://", "")
            property var disks: []
            // What Locations shows: not boot, EFI or swap partitions, nor the live USB's own.
            readonly property var volumes: {
                const out = []
                for (const d of disks) for (const v of d.volumes) {
                    const shown = v.mountpoint === "/" || v.mountpoint === "/home"
                        || (!v.system && !v.swap && !!v.fstype && !/EFI/i.test(v.name)
                            && !(v.fstype === "vfat" && !v.removable && v.capacity < 2e9))
                    if (shown) out.push(Object.assign({}, v, { diskName: d.name }))
                }
                return out
            }
            // The volume a path is on: the one mounted deepest above it.
            function volumeFor(p) {
                let best = null
                for (const v of volumes)
                    if (v.mountpoint && (p === v.mountpoint || p.startsWith(v.mountpoint === "/" ? "/" : v.mountpoint + "/"))
                        && (!best || v.mountpoint.length > best.mountpoint.length)) best = v
                return best
            }
            function openVolume(v) {
                if (v.mounted && v.mountpoint) { navigate(v.mountpoint); return }
                if (diskOp.running) return
                diskOp.kind = "mount"
                diskOp.command = ["python3", disksHelper, "mount", v.device]
                diskOp.running = true
            }
            function eject(v) {
                if (diskOp.running) return
                diskOp.kind = "eject"
                diskOp.volume = v
                diskOp.command = ["python3", disksHelper, "eject", v.disk || v.device]
                diskOp.running = true
            }
            function say(text) { notice = text; noticeTimer.restart() }

            // Two views that aren't folders: Recents and the Trash.
            readonly property bool inTrash: path === "trash:"
            readonly property bool inRecents: path === "recents:"
            readonly property bool inComputer: path === "computer:"
            readonly property bool special: inTrash || inRecents || inComputer

            readonly property string title: {
                if (inTrash) return "Trash"
                if (inRecents) return "Recents"
                if (inComputer) return "Computer"
                if (path === home) return "Home"
                const vol = volumeFor(path)
                if (vol && vol.mountpoint === path) return vol.name
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

            // The path bar: the disk, then each folder down to this one.
            readonly property var crumbs: {
                if (special) return []
                const vol = volumeFor(path)
                const root = vol ? vol.mountpoint : "/"
                const out = [{ name: vol ? vol.name : "Computer", path: root, kind: "drive" }]
                let acc = root === "/" ? "" : root
                for (const part of path.slice(root.length).split("/").filter((s) => s)) {
                    acc += "/" + part
                    out.push({ name: part, path: acc, kind: acc === home ? "house" : "folder" })
                }
                return out
            }

            function reload() {
                if (inComputer) {
                    // Computer: every volume, with the room left on it.
                    entries = volumes.map((v) => ({
                        name: v.name, path: v.mountpoint || "volume:" + v.device, folder: true,
                        icon: "drive-harddisk", size: 0, modified: 0, mime: "inode/directory", volume: v,
                        detail: v.mounted ? formatSize(v.free) + " free of " + formatSize(v.size) : "Not mounted"
                    }))
                    error = ""
                    loading = false
                    return
                }
                // One listing at a time; asked again meanwhile, it lists again after.
                if (listProc.running) {
                    listProc.again = true
                    return
                }
                loading = true
                error = ""
                listProc.asked = path
                listProc.command = ["python3", helper, "list", path, query, showHidden ? "hidden" : ""]
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
            // ⇧⌘. shows the files whose names start with a dot, as on the Mac.
            function toggleHidden() {
                showHidden = !showHidden
                reload()
            }
            function enclosingFolder() {
                if (special) return
                const up = path.replace(/\/[^/]+\/?$/, "") || "/"
                if (up !== path) navigate(up)
            }
            Keys.onPressed: (event) => {
                const ctrl = event.modifiers & Qt.ControlModifier
                const shift = event.modifiers & Qt.ShiftModifier
                const columns = view === "grid" ? Math.max(1, Math.floor(grid.width / grid.cellWidth)) : 1
                if (event.key === Qt.Key_Space || (ctrl && event.key === Qt.Key_Y)) {
                    if (selectedEntry || quickLook.open) quickLook.open = !quickLook.open
                } else if (event.key === Qt.Key_Escape && quickLook.open) quickLook.open = false
                else if (ctrl && (event.key === Qt.Key_O || event.key === Qt.Key_End)) {
                    if (selectedEntry) { quickLook.open = false; openEntry(selectedEntry) }
                } else if (ctrl && event.key === Qt.Key_Home) enclosingFolder()
                else if (ctrl && shift && (event.key === Qt.Key_Period || event.key === Qt.Key_Greater)) toggleHidden()
                else if (ctrl && shift && event.key === Qt.Key_C) navigate("computer:")
                else if (ctrl && shift && event.key === Qt.Key_H) navigate(home)
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
                if (entry.volume) {
                    openVolume(entry.volume)
                } else if (entry.folder) {
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
                    { text: showHidden ? "Hide Hidden Files" : "Show Hidden Files", shortcut: "⇧⌘.", action: () => toggleHidden() },
                    { text: "Computer", shortcut: "⇧⌘C", action: () => navigate("computer:") },
                    { text: "Open Disk Utility", action: () => Quickshell.execDetached(["gg-disk-utility"]) },
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
                property string asked: ""       // the folder this listing is for
                property bool again: false
                stdout: StdioCollector {
                    onStreamFinished: {
                        // Gone somewhere else while it was being read: not this one.
                        if (listProc.asked !== files.path) return
                        try {
                            const r = JSON.parse(text)
                            if (r.ok) {
                                files.path = r.path
                                files.entries = r.entries ?? []
                                files.free = r.free ?? -1
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
                onExited: {
                    files.loading = false
                    if (listProc.again) { listProc.again = false; files.reload() }
                }
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

            Process {
                id: diskProc
                running: true
                command: ["python3", files.disksHelper, "snapshot"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            const r = JSON.parse(text)
                            if (r.ok) {
                                files.disks = r.disks
                                if (files.inComputer) files.reload()
                            }
                        } catch (e) {}
                    }
                }
            }
            // Disks plugged in or out, volumes mounted or unmounted (by Files or
            // anything else): look again a moment later. Without udevadm and
            // findmnt, every fifteen seconds.
            Process {
                id: diskWatch
                running: true
                command: ["sh", "-c", "command -v udevadm >/dev/null || command -v findmnt >/dev/null || exit 3; "
                    + "{ command -v udevadm >/dev/null && stdbuf -oL udevadm monitor --udev --subsystem-match=block & } ; "
                    + "{ command -v findmnt >/dev/null && stdbuf -oL findmnt --poll -o ACTION,TARGET & } ; wait"]
                stdout: SplitParser { onRead: diskSettle.restart() }
                onExited: diskFallback.start()
            }
            Timer { id: diskSettle; interval: 600; onTriggered: if (!diskProc.running) diskProc.running = true }
            Timer {
                id: diskFallback
                interval: 15000
                onTriggered: { if (!diskProc.running) diskProc.running = true; diskWatch.running = true }
            }
            Timer { id: noticeTimer; interval: 4000; onTriggered: files.notice = "" }
            Process {
                id: diskOp
                property string kind: ""
                property var volume: null
                stdout: StdioCollector {
                    onStreamFinished: {
                        let r = null
                        try { r = JSON.parse(text) } catch (e) {}
                        if (!r || !r.ok) {
                            files.say(r?.error ?? (diskOp.kind === "mount" ? "The volume couldn't be opened." : "The disk couldn't be ejected."))
                        } else if (diskOp.kind === "mount" && r.mountpoint) {
                            files.navigate(r.mountpoint)
                        } else if (diskOp.kind === "eject") {
                            const v = diskOp.volume
                            if (v && v.mountpoint && (files.path === v.mountpoint || files.path.startsWith(v.mountpoint + "/")))
                                files.navigate(files.home)
                            files.say((v?.name ?? "The disk") + " can be unplugged now.")
                        }
                        diskProc.running = true
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
                anchors { fill: parent; margins: 18; topMargin: 0; bottomMargin: pathBar.visible ? pathBar.height + 4 : 18 }
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
                        Text {
                            visible: !!cell.modelData.detail
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: cell.modelData.detail ?? ""
                            color: Theme.secondaryLabel
                            font { family: Theme.fontUi; pixelSize: 10 }
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
                anchors { fill: parent; margins: 16; topMargin: 0; bottomMargin: pathBar.visible ? pathBar.height + 4 : 16 }
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

            // The path bar and status bar, as Finder's: the disk and the folders
            // down to this one (each opens on a click), the items and the room left.
            Rectangle {
                id: pathBar
                objectName: "filesPathBar"
                visible: !files.special && !files.loading
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 28
                color: Theme.contentBg
                Rectangle { width: parent.width; height: 1; color: Theme.separator }
                Item {
                    anchors { left: parent.left; leftMargin: 10; right: status.left; rightMargin: 12; top: parent.top; bottom: parent.bottom }
                    clip: true
                    Row {
                        id: crumbRow
                        anchors.verticalCenter: parent.verticalCenter
                        // A deep folder keeps its end in view.
                        x: Math.min(0, parent.width - implicitWidth)
                        spacing: 1
                        Repeater {
                            model: files.crumbs
                            delegate: Row {
                                id: crumb
                                required property var modelData
                                required property int index
                                spacing: 1
                                Symbol {
                                    visible: crumb.index > 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "chevron-small-right"; size: 11; tone: "gray"
                                }
                                Item {
                                    width: crumbContent.implicitWidth + 10; height: 22
                                    anchors.verticalCenter: parent.verticalCenter
                                    Rectangle {
                                        anchors.fill: parent; radius: 6
                                        color: crumbArea.pressed ? Theme.selection : crumbArea.containsMouse ? (Theme.dark ? "#12ffffff" : "#0a000000") : "transparent"
                                    }
                                    Row {
                                        id: crumbContent
                                        anchors.centerIn: parent
                                        spacing: 4
                                        Symbol { anchors.verticalCenter: parent.verticalCenter; name: crumb.modelData.kind; size: 12; tone: crumb.modelData.kind === "folder" ? "accent" : "gray" }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: crumb.modelData.name
                                            color: crumb.index === files.crumbs.length - 1 ? Theme.label : Theme.secondaryLabel
                                            font { family: Theme.fontUi; pixelSize: 11 }
                                        }
                                    }
                                    MouseArea {
                                        id: crumbArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: files.navigate(crumb.modelData.path)
                                    }
                                    DropArea {
                                        anchors.fill: parent
                                        onEntered: (drag) => drag.accepted = files.accepts(drag, crumb.modelData.path)
                                        onDropped: (drop) => files.dropOn(drop, crumb.modelData.path)
                                    }
                                }
                            }
                        }
                    }
                }
                Text {
                    id: status
                    objectName: "filesStatus"
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    text: files.notice || (files.entries.length + (files.entries.length === 1 ? " item" : " items")
                        + (files.free >= 0 ? ", " + files.formatSize(files.free) + " available" : ""))
                    color: files.notice ? Theme.label : Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: 11; weight: files.notice ? Font.Medium : Font.Normal }
                }
            }

            // Sizes as the Mac gives them: in thousands (1 GB is 1,000,000,000 bytes).
            function formatSize(bytes) {
                const units = ["bytes", "KB", "MB", "GB", "TB", "PB"]
                let n = Math.max(0, bytes), i = 0
                while (n >= 1000 && i < units.length - 1) { n /= 1000; i++ }
                return i === 0 ? n + " bytes" : (i === 1 || n >= 100 ? Math.round(n) : n.toFixed(1).replace(/\.0$/, "")) + " " + units[i]
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
