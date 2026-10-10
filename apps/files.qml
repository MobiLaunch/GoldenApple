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
        closeAction: () => files.requestClose()
        onBackRequested: files.goBack()
        onForwardRequested: files.goForward()
        implicitWidth: Math.min(1050, (Quickshell.screens[0]?.width ?? 1280) - 80)
        implicitHeight: Math.min(700, (Quickshell.screens[0]?.height ?? 900) - 130)
        minimumSize: Qt.size(720, 440)
        property bool sidebarShown: !win.tabletCompact
        sidebarWidth: sidebarShown ? (win.tabletCompact ? Math.min(300, win.width * 0.46) : 210) : 0
        fullSizeContent: true
        background: Theme.contentBg

        toolbarSidebar: [
            ToolbarButton { round: true; symbol: "sidebar"; checked: win.sidebarShown; onClicked: win.sidebarShown = !win.sidebarShown }
        ]

        toolbarItems: [
            Row {
                x: Math.max(win.contentX + 12, win.toolbarLeadingEnd)
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
                    width: Math.max(80, Math.min(180, files.width - 400))
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: files.title
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.Bold }
                    }
                    Text {
                        width: parent.width; elide: Text.ElideRight
                        text: files.selectedPaths.length ? files.selectedPaths.length + " selected" : files.entries.length + (files.entries.length === 1 ? " item" : " items")
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(10) }
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
                        onClicked: files.switchView("grid")
                    }
                    ToolbarButton {
                        symbol: "list"
                        checked: files.view === "list"
                        onClicked: files.switchView("list")
                    }
                }

                Button {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: files.inTrash
                    enabled: files.entries.length > 0 && !files.busy
                    text: "Empty"
                    onClicked: files.askEmptyTrash()
                }

                ToolbarButton {
                    round: true
                    symbol: "folder"
                    enabled: !files.special && !files.busy
                    onClicked: {
                        files.dialogMode = "new"
                        files.dialogText = "untitled folder"
                        editDialog.open()
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
                    width: Math.max(110, Math.min(190, files.width * 0.25))
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
            Flickable {
                id: placesFlick
                objectName: "filesSidebarScroll"
                anchors.fill: parent; clip: true
                contentHeight: placesColumn.height + 8
                boundsBehavior: Flickable.StopAtBounds
                activeFocusOnTab: true
                // Roving arrow-key focus crosses Favorites and mounted volumes.
                // Only pressing a row activates it; browsing the sidebar does
                // not change the open folder or lose the document selection.
                function navigableRows() {
                    const out = []
                    for (let i = 0; i < favoriteRows.count; i++) {
                        const item = favoriteRows.itemAt(i)
                        if (item && item.visible && item.enabled) out.push(item)
                    }
                    for (let i = 0; i < volumeRows.count; i++) {
                        const item = volumeRows.itemAt(i)
                        if (item && item.visible && item.enabled) out.push(item)
                    }
                    return out
                }
                function focusRow(step, edge) {
                    const rows = navigableRows()
                    if (!rows.length) return
                    let index = rows.findIndex((r) => r.activeFocus)
                    if (index < 0) index = rows.findIndex((r) => r.selected)
                    const next = edge === "first" ? 0 : edge === "last" ? rows.length - 1
                        : Math.max(0, Math.min(rows.length - 1, index < 0 ? (step < 0 ? rows.length - 1 : 0) : index + step))
                    rows[next].forceActiveFocus()
                    ensureVisible(rows[next])
                }
                Keys.onPressed: (event) => {
                    if (event.modifiers & (Qt.ControlModifier | Qt.MetaModifier | Qt.AltModifier)) return
                    if (event.key === Qt.Key_Down) focusRow(1)
                    else if (event.key === Qt.Key_Up) focusRow(-1)
                    else if (event.key === Qt.Key_Home) focusRow(0, "first")
                    else if (event.key === Qt.Key_End) focusRow(0, "last")
                    else return
                    event.accepted = true
                }
                function ensureVisible(row) {
                    if (!row.activeFocus) return
                    if (row.y < contentY) contentY = Math.max(0, row.y - 8)
                    else if (row.y + row.height > contentY + height) contentY = Math.max(0, Math.min(contentHeight - height, row.y + row.height - height + 8))
                }
                Behavior on contentY { enabled: !Theme.reduceMotion; NumberAnimation { duration: 120 } }
            Column {
                id: placesColumn
                width: placesFlick.width
                spacing: 2
                Text {
                    width: parent.width - 12; x: 8
                    text: "Favorites"; color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: Theme.fs(11); weight: Font.DemiBold }
                }
                Item { width: 1; height: 6 }

                Repeater {
                    id: favoriteRows
                    model: files.locations
                    delegate: SidebarRow {
                        id: place
                        required property var modelData
                        width: parent.width
                        text: modelData.name
                        symbol: modelData.icon
                        selected: files.path === modelData.path || placeDrop.containsDrag
                        onActiveFocusChanged: placesFlick.ensureVisible(place)
                        onClicked: files.navigate(modelData.path)
                        // Drop on a place to move there; on the Trash to throw away.
                        DropArea {
                            id: placeDrop
                            anchors.fill: parent
                            enabled: place.modelData.path !== "recents:"
                            onEntered: (drag) => drag.accepted = place.modelData.path === "trash:"
                                ? files.pathsOf(drag.urls).length > 0 && !files.inTrash && !files.busy
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
                    font { family: Theme.fontUi; pixelSize: Theme.fs(11); weight: Font.DemiBold }
                }
                Item { width: 1; height: 4; visible: files.volumes.length > 0 }
                Repeater {
                    id: volumeRows
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
                        onActiveFocusChanged: placesFlick.ensureVisible(volumeRow)
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
                Scroller { parent: placesFlick; flickable: placesFlick }
            }
        ]

        FocusScope {
            id: files
            objectName: "filesApp"
            anchors.fill: parent
            focus: true

            readonly property string helper: Qt.resolvedUrl("files/helper.py").toString().replace("file://", "")
            readonly property string archiveHelper: Qt.resolvedUrl("archive/helper.py").toString().replace("file://", "")
            readonly property string home: Quickshell.env("HOME")
            property string path: Quickshell.env("GG_FILES_PATH") || home
            property string initialSelect: Quickshell.env("GG_FILES_SELECT") || ""
            property var listing: []
            readonly property var entries: sorted(listing)
            property var back: []
            property var forward: []
            property string selectedPath: ""
            property var selectedPaths: []
            property string selectionAnchor: ""
            // Finder-style type-to-select. This buffer is ephemeral: it never
            // alters the toolbar search query or the directory listing.
            property string typeAhead: ""
            Timer {
                id: typeAheadDwell
                interval: 950
                onTriggered: files.typeAhead = ""
            }
            readonly property string selectedName: selectedEntry?.name ?? ""
            readonly property bool selectedFolder: selectedEntry?.folder ?? false
            property string view: "grid"
            property string sortKey: "name"
            property bool descending: false
            property string query: ""
            property bool loading: false
            property string error: ""
            property string dialogMode: ""
            property string dialogText: ""
            property string pendingOp: ""
            property bool showHidden: false
            property real free: -1              // space left on this folder's disk
            property string notice: ""          // a passing word in the path bar (an eject that failed)
            readonly property bool busy: opProc.running || transferProc.running || undoProc.running || archiveProc.running
            property var undoStack: []
            property var info: ({})
            property var cutPaths: []
            property var preferences: ({folders: {}})
            property bool prefsReady: false
            property bool prefsApplying: false
            property bool prefsFailed: false
            property string prefsPending: ""
            property string prefsSaved: ""
            property var transferRequest: ({})
            property var transferState: ({})
            property var transferResult: null
            property var conflict: null
            property bool cancelRequested: false
            property bool closeAfterTransfer: false
            property var selectionAfterReload: []
            readonly property string worker: Qt.resolvedUrl("files/operations.py").toString().replace("file://", "")
            readonly property var selectedEntries: entries.filter((e) => selectedPaths.includes(e.path))
            function sorted(rows) {
                const out = rows.slice()
                out.sort((a, b) => {
                    if (sortKey === "name" && a.folder !== b.folder) return a.folder ? -1 : 1
                    let cmp = sortKey === "modified" || sortKey === "size" ? (a[sortKey] - b[sortKey])
                        : String(sortKey === "kind" ? a.mime : a.name).localeCompare(String(sortKey === "kind" ? b.mime : b.name), undefined, {numeric:true, sensitivity:"base"})
                    if (!cmp) cmp = a.path.localeCompare(b.path)
                    return descending ? -cmp : cmp
                })
                return out
            }
            function rememberView() {
                if (!prefsReady || prefsApplying) return
                const folders = Object.assign({}, preferences.folders ?? {})
                folders[path] = {view:view, sortKey:sortKey, descending:descending}
                preferences = {folders:folders, lastPath:path, showHidden:showHidden}
                prefsDebounce.restart()
            }
            function restoreView() {
                prefsApplying = true
                const p = preferences.folders?.[path] ?? {}
                view = p.view === "list" ? "list" : "grid"
                sortKey = ["name", "modified", "size", "kind"].includes(p.sortKey) ? p.sortKey : "name"
                descending = !!p.descending
                prefsApplying = false
            }
            function switchView(next) {
                if (next !== "grid" && next !== "list") return
                if (view === next) { forceActiveFocus(); return }
                const before = view === "grid" ? grid : list
                const after = next === "grid" ? grid : list
                const oldRange = Math.max(0, before.contentHeight - before.height)
                const fraction = oldRange > 0
                    ? Math.max(0, Math.min(1, (before.contentY - before.originY) / oldRange))
                    : 0
                const keepSelection = selectedIndex
                view = next
                forceActiveFocus()
                // Wait for the incoming GridView/ListView to establish its new
                // geometry. The old view stays painted for its short crossfade,
                // but gives up interaction immediately.
                Qt.callLater(() => {
                    if (view !== next || loading || error) return
                    if (keepSelection >= 0 && keepSelection < entries.length) {
                        after.positionViewAtIndex(keepSelection,
                            next === "grid" ? GridView.Contain : ListView.Contain)
                    } else {
                        const newRange = Math.max(0, after.contentHeight - after.height)
                        after.contentY = after.originY + fraction * newRange
                    }
                })
            }
            onViewChanged: rememberView()
            onSortKeyChanged: rememberView()
            onDescendingChanged: rememberView()
            onShowHiddenChanged: rememberView()
            onPathChanged: {
                typeAheadDwell.stop()
                typeAhead = ""
                clearSelection()
                if (prefsReady) { restoreView(); rememberView() }
            }
            function clearSelection() { selectedPaths = []; selectedPath = ""; selectionAnchor = "" }
            function setSelection(paths, primary) {
                selectedPaths = Array.from(new Set(paths))
                selectedPath = selectedPaths.includes(primary) ? primary : selectedPaths[selectedPaths.length - 1] ?? ""
            }
            function selectAll() { setSelection(entries.map((e) => e.path), entries[0]?.path); selectionAnchor = selectedPath; forceActiveFocus() }
            function clipboard(mode) {
                if (!selectedPaths.length || inTrash || inComputer || clipboardProc.running) return
                clipboardProc.mode = mode
                clipboardProc.request = {paths:selectedPaths.slice(), mode:mode}
                clipboardProc.command = ["python3", helper, "clipboard-write"]
                clipboardProc.running = true
                forceActiveFocus()
            }
            function paste(move) {
                if (special || busy || clipboardProc.running) { say("Wait for the current operation to finish, then paste."); return }
                clipboardProc.mode = "paste"
                clipboardProc.move = !!move
                clipboardProc.destination = path
                clipboardProc.command = ["python3", helper, "clipboard-read"]
                clipboardProc.running = true
                forceActiveFocus()
            }
            function startTransfer(paths, dest, mode) {
                if (busy) { say("An operation is already running. Wait or cancel it before starting another."); return }
                if (!paths.length) return
                transferRequest = {paths:paths.slice(), destination:dest, mode:mode, conflicts:mode === "duplicate" ? "keep-both" : "ask"}
                transferResult = null; transferState = {event:"preparing",total:paths.length}; conflict = null; cancelRequested = false
                transferProc.finishedEvent = false
                transferProc.running = true
                forceActiveFocus()
            }
            function duplicate() { if (!inTrash && !inComputer) startTransfer(selectedPaths, "", "duplicate") }
            function cancelTransfer() {
                if (!transferProc.running || cancelRequested) return
                cancelRequested = true; conflict = null
                transferProc.write(JSON.stringify({cancel:true}) + "\n")
            }
            function answerConflict(answer) {
                transferProc.write(JSON.stringify({answer:answer, all:conflictAll.checked}) + "\n")
                conflict = null
            }
            function takeTransfer(line) {
                let r
                try { r = JSON.parse(line) } catch (e) { return }
                if (r.event === "conflict") { conflictAll.checked = false; conflict = r; return }
                if (r.event !== "finished") { transferState = Object.assign({}, transferState, r); return }
                transferProc.finishedEvent = true
                transferResult = r; conflict = null
                selectionAfterReload = (r.completed ?? []).map((item) => item.path)
                cutPaths = cutPaths.filter((p) => !(r.completed ?? []).some((item) => item.source === p && item.action === "move"))
                reload()
            }
            function undoLast() {
                if (busy || !undoStack.length) return
                undoProc.record = undoStack[undoStack.length - 1]
                undoProc.running = true
            }
            function getInfo() {
                if (!selectedEntry || selectedPaths.length !== 1 || infoProc.running) return
                infoProc.command = ["python3", helper, "info", selectedPath]; infoProc.running = true
            }
            function requestClose() {
                if (busy || clipboardProc.running) {
                    say("An operation is running. Wait for it to finish or cancel the transfer before closing.")
                    return
                }
                if (prefsFailed) { Qt.quit(); return }
                prefsDebounce.stop()
                closeAfterTransfer = true
                savePreferences()
            }
            function savePreferences() {
                if (prefsWriter.running) return
                const text = JSON.stringify(preferences)
                if (!prefsReady || text === prefsSaved) { if (closeAfterTransfer) Qt.quit(); return }
                prefsPending = text; prefsWriter.running = true
            }

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
                    listing = volumes.map((v) => ({
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
                clearSelection()
                query = ""
                toolbarSearch.text = ""
                reload()
                files.forceActiveFocus()
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
                forceActiveFocus()
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
                forceActiveFocus()
            }

            function select(entry, modifiers) {
                const ctrl = (modifiers ?? 0) & Qt.ControlModifier
                const shift = (modifiers ?? 0) & Qt.ShiftModifier
                if (shift) {
                    let anchor = entries.findIndex((e) => e.path === selectionAnchor)
                    if (anchor < 0) anchor = Math.max(0, selectedIndex)
                    const index = entries.findIndex((e) => e.path === entry.path)
                    const range = entries.slice(Math.min(anchor, index), Math.max(anchor, index) + 1).map((e) => e.path)
                    setSelection(ctrl ? selectedPaths.concat(range) : range, entry.path)
                } else if (ctrl) {
                    setSelection(selectedPaths.includes(entry.path) ? selectedPaths.filter((p) => p !== entry.path) : selectedPaths.concat([entry.path]), entry.path)
                    selectionAnchor = entry.path
                } else {
                    setSelection([entry.path], entry.path)
                    selectionAnchor = entry.path
                }
                files.forceActiveFocus()
            }

            // The keyboard, as in Finder: arrows move the selection (by rows in
            // the grid), Space or ⌘Y is Quick Look, Return renames, ⌘O or ⌘↓
            // opens, ⌘↑ goes to the enclosing folder, ⌘⌫ moves to the Trash.
            // (keyd sends ⌘ shortcuts as Ctrl, and ⌘↑ ⌘↓ as Ctrl+Home/End.)
            readonly property int selectedIndex: entries.findIndex((e) => e.path === selectedPath)
            readonly property var selectedEntry: selectedIndex >= 0 ? entries[selectedIndex] : null
            function selectAtIndex(index, modifiers) {
                if (!entries.length) return
                const i = Math.max(0, Math.min(entries.length - 1, index))
                select(entries[i], modifiers)
                if (view === "grid") grid.positionViewAtIndex(i, GridView.Contain)
                else list.positionViewAtIndex(i, ListView.Contain)
            }
            function moveSelection(step, modifiers) {
                // An arrow or page gesture ends the unfinished name prefix,
                // so the next typed letter starts a new search.
                typeAheadDwell.stop()
                typeAhead = ""
                selectAtIndex(selectedIndex < 0 ? 0 : selectedIndex + step, modifiers)
            }
            function typeSelect(letter) {
                if (!entries.length || editDialog.shown || confirmEmpty.shown
                    || infoDialog.shown || !!conflict || quickLook.open) return false
                const char = letter.toLocaleLowerCase()
                // Repeating a single character cycles through matching names;
                // a multi-character sequence narrows the prefix instead.
                const cycling = typeAhead === char
                let prefix = cycling ? char : typeAhead + char
                function find(from, query) {
                    for (let n = 0; n < entries.length; n++) {
                        const i = (from + n) % entries.length
                        if (entries[i].name.toLocaleLowerCase().startsWith(query)) return i
                    }
                    return -1
                }
                let i = find(cycling ? Math.max(0, selectedIndex + 1) : 0, prefix)
                if (i < 0 && typeAhead && !cycling) {
                    prefix = char
                    i = find(Math.max(0, selectedIndex + 1), prefix)
                }
                typeAhead = prefix
                typeAheadDwell.restart()
                if (i >= 0) selectAtIndex(i, 0)
                return true
            }
            function rename() {
                if (!selectedEntry || selectedPaths.length !== 1 || inTrash || inComputer || busy) return
                dialogMode = "rename"
                dialogText = selectedName
                editDialog.open()
                Qt.callLater(() => dialogField.input.forceActiveFocus())
            }
            // ⇧⌘. shows the files whose names start with a dot, as on the Mac.
            function toggleHidden() {
                showHidden = !showHidden
                reload()
                forceActiveFocus()
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
                if (ctrl && event.key === Qt.Key_A) selectAll()
                else if (ctrl && !shift && event.key === Qt.Key_C) clipboard("copy")
                else if (ctrl && event.key === Qt.Key_X) clipboard("cut")
                else if (ctrl && event.key === Qt.Key_V) paste(shift)
                else if (ctrl && event.key === Qt.Key_D) duplicate()
                else if (ctrl && event.key === Qt.Key_I) getInfo()
                else if (ctrl && event.key === Qt.Key_Z) undoLast()
                else if (event.key === Qt.Key_Space || (ctrl && event.key === Qt.Key_Y)) {
                    if (selectedEntry || quickLook.open) quickLook.open = !quickLook.open
                } else if (event.key === Qt.Key_Escape && quickLook.open) quickLook.open = false
                else if (ctrl && (event.key === Qt.Key_O || event.key === Qt.Key_End)) {
                    if (selectedEntry) { quickLook.open = false; openSelection() }
                } else if (ctrl && event.key === Qt.Key_Home) enclosingFolder()
                else if (ctrl && shift && (event.key === Qt.Key_Period || event.key === Qt.Key_Greater)) toggleHidden()
                else if (ctrl && shift && event.key === Qt.Key_C) navigate("computer:")
                else if (ctrl && shift && event.key === Qt.Key_H) navigate(home)
                else if (ctrl && event.key === Qt.Key_Backspace) {
                    if (selectedPaths.length && !inTrash && !inComputer) runOperation(["trash"].concat(selectedPaths), "trash")
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (!quickLook.open) rename()
                } else if (event.key === Qt.Key_Escape) {
                    typeAheadDwell.stop()
                    typeAhead = ""
                    clearSelection()
                }
                else if (!ctrl && (event.key === Qt.Key_Home || event.key === Qt.Key_End)) {
                    typeAheadDwell.stop()
                    typeAhead = ""
                    selectAtIndex(event.key === Qt.Key_Home ? 0 : entries.length - 1, event.modifiers)
                }
                else if (!ctrl && (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown)) {
                    const rows = view === "grid" ? Math.max(1, Math.floor(grid.height / grid.cellHeight))
                        : Math.max(1, Math.floor(list.height / 36))
                    moveSelection((event.key === Qt.Key_PageDown ? 1 : -1) * rows * columns, event.modifiers)
                }
                else if (!ctrl && event.key === Qt.Key_Left && view === "grid") moveSelection(-1, event.modifiers)
                else if (!ctrl && event.key === Qt.Key_Right && view === "grid") moveSelection(1, event.modifiers)
                else if (!ctrl && event.key === Qt.Key_Up) moveSelection(-columns, event.modifiers)
                else if (!ctrl && event.key === Qt.Key_Down) moveSelection(columns, event.modifiers)
                else if (!(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
                    && event.text.length === 1 && event.text.trim().length === 1) {
                    if (!typeSelect(event.text)) return
                } else return
                event.accepted = true
            }

            function isArchivePath(path) {
                return /\.(zip|cbz|tar|tar\.gz|tgz|tar\.xz|txz|tar\.bz2|tbz|tbz2)$/i.test(String(path))
            }
            function archiveAction(action) {
                if (busy || inTrash || inComputer || !selectedPaths.length) return
                const selected = selectedPaths.slice()
                if (action === "extract" && (selected.length !== 1 || !isArchivePath(selected[0]))) return
                archiveProc.completed = null
                archiveProc.command = ["python3", archiveHelper, action].concat(selected)
                archiveProc.running = true
                say(action === "create" ? "Compressing selection…" : "Extracting archive…")
            }
            function openEntry(entry) {
                if (entry.volume) {
                    openVolume(entry.volume)
                } else if (entry.folder) {
                    navigate(entry.path)
                } else if (isArchivePath(entry.path)) {
                    Quickshell.execDetached(["gg-archive", entry.path])
                } else {
                    runOperation(["open", entry.path], "open")
                }
            }

            function runOperation(args, kind) {
                if (busy) { say("An operation is already running. Wait or cancel the transfer first."); return }
                pendingOp = kind
                error = ""
                opProc.command = ["python3", helper].concat(args)
                opProc.running = true
            }
            function openSelection() {
                if (selectedEntries.length === 1) openEntry(selectedEntry)
                else if (selectedEntries.length > 1 && !inComputer) runOperation(["open"].concat(selectedPaths), "open")
            }

            // ---------------------------------------------------- Trash
            function putBack(entry) {
                const names = selectedEntries.filter((e) => e.trashName).map((e) => e.trashName)
                if (names.length) runOperation(["put-back"].concat(names), "put-back")
            }
            function askEmptyTrash() { confirmEmpty.open() }
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
                return !busy && paths.length > 0 && !paths.some((p) => dest === p || dest.startsWith(p + "/"))
            }
            function dropOn(drop, dest) {
                if (busy) { say("Wait for the current operation before dropping items."); return }
                const paths = pathsOf(drop.urls)
                if (!paths.length) return
                const ours = drop.source !== null && drop.source !== undefined
                if (dest === "trash:") {
                    runOperation(["trash"].concat(paths), "trash")
                    drop.accept(Qt.MoveAction)
                    return
                }
                const copy = !ours || drop.proposedAction === Qt.CopyAction
                startTransfer(paths, dest, copy ? "copy" : "auto")
                drop.accept(copy ? Qt.CopyAction : Qt.MoveAction)
            }

            // An item's menu (right-click), for where it is.
            function itemMenu(anchor, x, y, entry) {
                if (!selectedPaths.includes(entry.path)) select(entry)
                if (entry.volume) {
                    menu.popup(anchor, x, y, [{text:"Open Volume", action:()=>openVolume(entry.volume)},
                        {text:"Open Disk Utility", action:()=>Quickshell.execDetached(["gg-disk-utility"])}])
                    return
                }
                const items = inTrash ? [
                    { text: "Put Back", action: () => putBack(entry) },
                    { text: "Quick Look", shortcut: "Space", action: () => quickLook.open = true },
                    { separator: true },
                    { text: "Empty Trash", destructive: true, action: () => askEmptyTrash() }
                ] : [
                    { text: "Open", action: () => openSelection() },
                    { text: "Quick Look", shortcut: "Space", action: () => quickLook.open = true }
                ].concat(inRecents ? [{ text: "Show in Enclosing Folder", action: () => showInFolder(entry) }] : [], [
                    { text: "Extract Here", enabled: selectedPaths.length === 1 && isArchivePath(entry.path) && !busy,
                      action: () => archiveAction("extract") },
                    { text: "Compress" + (selectedPaths.length > 1 ? " " + selectedPaths.length + " Items" : " to ZIP"),
                      enabled: selectedPaths.length > 0 && !busy && !special,
                      action: () => archiveAction("create") },
                    { text: "Rename", enabled: selectedPaths.length === 1 && !busy, action: () => rename() },
                    { text: "Get Info", shortcut: "⌘I", enabled: selectedPaths.length === 1, action: () => getInfo() },
                    { text: "Copy", shortcut: "⌘C", action: () => clipboard("copy") },
                    { text: "Cut", shortcut: "⌘X", action: () => clipboard("cut") },
                    { text: "Duplicate", shortcut: "⌘D", enabled: !busy, action: () => duplicate() },
                    { text: "Share with AirDrop…", enabled: selectedPaths.length === 1, action: () => Quickshell.execDetached(["gg-airdrop", entry.path]) },
                    { separator: true },
                    { text: "Move to Trash", enabled: !busy, action: () => runOperation(["trash"].concat(selectedPaths), "trash") }
                ])
                menu.popup(anchor, x, y, items)
            }

            function openActions(anchor) {
                if (inTrash) {
                    menu.popup(anchor, 0, anchor.height + 6, [
                        { text: "Put Back", enabled: !!selectedEntry && !busy, action: () => putBack(selectedEntry) },
                        { text: "Quick Look", shortcut: "Space", enabled: !!selectedPath, action: () => quickLook.open = true },
                        { separator: true },
                        { text: "Empty Trash", destructive: true, enabled: entries.length > 0, action: () => askEmptyTrash() }
                    ])
                    return
                }
                const actions = [
                    { text: "New Folder", enabled: !special && !busy, action: () => {
                        dialogMode = "new"
                        dialogText = "untitled folder"
                        editDialog.open()
                        Qt.callLater(() => dialogField.input.forceActiveFocus())
                    }},
                    { separator: true },
                    { text: "Open", enabled: !!selectedPath, action: () => openSelection() },
                    { text: "Quick Look", shortcut: "Space", enabled: !!selectedPath, action: () => quickLook.open = true },
                    { text: "Extract Here", enabled: selectedPaths.length === 1 && isArchivePath(selectedPath) && !busy,
                      action: () => archiveAction("extract") },
                    { text: "Compress to ZIP", enabled: !!selectedPath && !special && !busy,
                      action: () => archiveAction("create") },
                    { text: "Rename", enabled: selectedPaths.length === 1 && !inComputer && !busy, action: () => rename() },
                    { text: "Get Info", shortcut: "⌘I", enabled: selectedPaths.length === 1 && !inComputer, action: () => getInfo() },
                    { text: "Select All", shortcut: "⌘A", action: () => selectAll() },
                    { text: "Copy", shortcut: "⌘C", enabled: !!selectedPath && !inComputer, action: () => clipboard("copy") },
                    { text: "Cut", shortcut: "⌘X", enabled: !!selectedPath && !inComputer, action: () => clipboard("cut") },
                    { text: "Paste", shortcut: "⌘V", enabled: !special && !busy, action: () => paste(false) },
                    { text: "Move Items Here", shortcut: "⇧⌘V", enabled: !special && !busy, action: () => paste(true) },
                    { text: "Duplicate", shortcut: "⌘D", enabled: !!selectedPath && !inComputer && !busy, action: () => duplicate() },
                    { text: undoStack.length ? "Undo " + (undoStack[undoStack.length - 1].kind === "rename" ? "Rename" : "New Folder") : "Undo", shortcut: "⌘Z", enabled: undoStack.length > 0 && !busy, action: () => undoLast() },
                    { text: "Show in Enclosing Folder", enabled: inRecents && !!selectedEntry, action: () => showInFolder(selectedEntry) },
                    { text: "Share with AirDrop…", enabled: !!selectedPath, action: () => Quickshell.execDetached(["gg-airdrop", selectedPath]) },
                    { text: "Move to Trash", enabled: !!selectedPath && !inComputer && !busy, action: () => runOperation(["trash"].concat(selectedPaths), "trash") },
                    { separator: true },
                    { text: "Sort by Name" + (sortKey === "name" ? " ✓" : ""), action: () => sortKey = "name" },
                    { text: "Sort by Date Modified" + (sortKey === "modified" ? " ✓" : ""), action: () => sortKey = "modified" },
                    { text: "Sort by Size" + (sortKey === "size" ? " ✓" : ""), action: () => sortKey = "size" },
                    { text: "Sort by Kind" + (sortKey === "kind" ? " ✓" : ""), action: () => sortKey = "kind" },
                    { text: descending ? "Ascending Order" : "Descending Order", action: () => descending = !descending },
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
                editDialog.close()
            }

            Component.onCompleted: if (prefsReady) reload()

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
                                files.listing = r.entries ?? []
                                files.setSelection(files.selectionAfterReload.length ? files.selectionAfterReload.filter((p) => files.entries.some((e) => e.path === p))
                                    : files.selectedPaths.filter((p) => files.entries.some((e) => e.path === p)), files.selectedPath)
                                files.selectionAfterReload = []
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
                            if (!r.ok) {
                                files.say(r.error ?? "The operation could not be completed.")
                                if (files.pendingOp !== "open") files.reload()
                            } else if (files.pendingOp !== "open") {
                                if (r.undo) files.undoStack = files.undoStack.concat([r.undo]).slice(-30)
                                files.selectionAfterReload = r.path ? [r.path] : []
                                files.reload()
                            }
                        } catch (e) {
                            files.say("The operation could not be completed.")
                        }
                    }
                }
            }

            // The worker writes structured JSON, never executes filenames.
            Process {
                id: archiveProc
                property var completed: null
                stdout: SplitParser {
                    onRead: (line) => {
                        try {
                            const event = JSON.parse(line)
                            if (event.event === "done") archiveProc.completed = event
                        } catch (e) {}
                    }
                }
                stderr: StdioCollector { id: archiveError }
                onExited: (code) => {
                    const r = archiveProc.completed
                    if (code !== 0 || !r?.ok) {
                        files.say(r?.error || archiveError.text.trim() || "The archive operation failed.")
                        return
                    }
                    files.selectionAfterReload = r.destination ? [r.destination] : []
                    files.reload()
                    files.say(r.mode === "create" ? "ZIP archive created." : "Archive extracted.")
                }
            }
            Process {
                id: transferProc
                property bool finishedEvent: false
                command: ["python3", files.worker]
                stdinEnabled: true
                onStarted: write(JSON.stringify(files.transferRequest) + "\n")
                stdout: SplitParser { onRead: (line) => files.takeTransfer(line) }
                stderr: StdioCollector { id: transferErr }
                onExited: (code) => {
                    if (!finishedEvent) files.transferResult = {ok:false, completed:[], skipped:[], errors:[{error:transferErr.text || "The transfer stopped unexpectedly. Check the destination before retrying."}]}
                    files.conflict = null
                }
            }
            Process {
                id: clipboardProc
                property string mode: ""
                property var request: ({})
                property string destination: ""
                property bool move: false
                stdinEnabled: true
                stdout: StdioCollector { id: clipboardOut }
                onStarted: { if (mode !== "paste") write(JSON.stringify(request)); stdinEnabled = false }
                onExited: (code) => {
                    stdinEnabled = true
                    let r = ({})
                    try { r = JSON.parse(clipboardOut.text) } catch (e) {}
                    if (!r.ok) { files.say(r.error || "The clipboard isn't available."); return }
                    if (mode === "paste") files.startTransfer(r.paths ?? [], destination, move ? "move" : r.mode)
                    else {
                        files.cutPaths = mode === "cut" ? request.paths.slice() : []
                        files.say(request.paths.length + (mode === "cut" ? " items ready to move." : " items copied. Paste them into a folder."))
                    }
                }
            }
            Process {
                id: undoProc
                property var record: ({})
                command: ["python3", files.helper, "undo"]
                stdinEnabled: true
                stdout: StdioCollector { id: undoOut }
                onStarted: { write(JSON.stringify(record)); stdinEnabled = false }
                onExited: (code) => {
                    stdinEnabled = true
                    let r = ({})
                    try { r = JSON.parse(undoOut.text) } catch (e) {}
                    if (!r.ok) { files.say(r.error || "The operation couldn't be undone."); return }
                    files.undoStack = files.undoStack.slice(0, -1).map((item) => item.kind === "mkdir" && item.path === r.path && JSON.stringify(item.identity) === JSON.stringify(r.identity)
                        ? Object.assign({}, item, {created:r.created}) : item)
                    files.selectionAfterReload = r.path ? [r.path] : []
                    files.reload(); files.say("Operation undone.")
                }
            }
            Process {
                id: infoProc
                stdout: StdioCollector { id: infoOut }
                onExited: (code) => {
                    let r = ({})
                    try { r = JSON.parse(infoOut.text) } catch (e) {}
                    if (!r.ok) { files.say(r.error || "Files couldn't read this item's information."); return }
                    files.info = r.info; infoDialog.open()
                }
            }
            Process {
                id: prefsReader
                running: true
                command: ["python3", files.helper, "prefs-load"]
                stdout: StdioCollector { id: prefsReadOut }
                onExited: {
                    let r = ({})
                    try { r = JSON.parse(prefsReadOut.text) } catch (e) {}
                    files.prefsApplying = true
                    if (r.ok) {
                        files.preferences = r.preferences ?? {folders:{}}
                        if (!Quickshell.env("GG_FILES_PATH") && !files.initialSelect && files.preferences.lastPath) files.path = files.preferences.lastPath
                        files.showHidden = !!files.preferences.showHidden
                        if (r.warning) files.say(r.warning)
                    } else files.say(r.error || "View preferences couldn't be restored.")
                    files.restoreView(); files.prefsReady = true; files.prefsApplying = false
                    files.prefsSaved = JSON.stringify(files.preferences)
                    files.rememberView(); files.reload()
                }
            }
            Timer { id: prefsDebounce; interval: 400; onTriggered: files.savePreferences() }
            Process {
                id: prefsWriter
                command: ["python3", files.helper, "prefs-save"]
                stdinEnabled: true
                stdout: StdioCollector { id: prefsWriteOut }
                onStarted: { write(files.prefsPending); stdinEnabled = false }
                onExited: (code) => {
                    stdinEnabled = true
                    let r = ({})
                    try { r = JSON.parse(prefsWriteOut.text) } catch (e) {}
                    if (!r.ok) {
                        files.say(r.error || "View preferences couldn't be saved.")
                        files.prefsFailed = true; files.closeAfterTransfer = false; return
                    }
                    files.prefsFailed = false
                    files.prefsSaved = files.prefsPending
                    Qt.callLater(() => files.savePreferences())
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
                Drag.active: !!area && area.drag.active && !files.inTrash && !files.inComputer && !files.busy
                Drag.dragType: Drag.Automatic
                Drag.supportedActions: Qt.MoveAction | Qt.CopyAction
                Drag.proposedAction: Qt.MoveAction
                Drag.mimeData: ({ "text/uri-list": (files.selectedPaths.includes(entry?.path) ? files.selectedPaths : [entry?.path ?? ""]).map((p) => Paths.fileUrl(p)).join("\r\n") + "\r\n" })
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
                objectName: "filesGridView"
                readonly property bool activeView: files.view === "grid" && !files.loading && !files.error
                opacity: activeView ? 1 : 0
                visible: opacity > 0.001
                enabled: activeView
                Behavior on opacity {
                    NumberAnimation { duration: Theme.reduceMotion ? 0 : 125; easing.type: Easing.OutCubic }
                }
                // The window draws under its toolbar; the grid starts below it and
                // scrolls up under it (clipped at the window, not at the toolbar).
                anchors { fill: parent; margins: 18; topMargin: 0; bottomMargin: (pathBar.visible ? pathBar.height : 0) + (transferPanel.visible ? transferPanel.height : 0) + 4 }
                topMargin: win.toolbarHeight + 10
                cellWidth: 118
                cellHeight: 112
                model: files.entries

                // Drag across empty grid space to select a rectangle of icons.
                // The background sits BEHIND item delegates, so an icon drag
                // still goes through the existing DragSource/DropArea path.
                MouseArea {
                    id: marqueeBackground
                    objectName: "filesMarqueeBackground"
                    anchors.fill: parent
                    z: -1
                    enabled: grid.activeView && !files.busy
                    acceptedButtons: Qt.LeftButton
                    preventStealing: true
                    property real startX: 0
                    property real startY: 0
                    property real lastX: 0
                    property real lastY: 0
                    property bool dragging: false
                    property bool hadDrag: false
                    property var originalPaths: []
                    property int modifiers: 0

                    function selectionBetween(x0, y0, x1, y1) {
                        const left = Math.min(x0, x1), right = Math.max(x0, x1)
                        const top = Math.min(y0, y1), bottom = Math.max(y0, y1)
                        const paths = []
                        // Only inspect rows inside the visible selection box.
                        // Scanning every file on every pointer move would stutter
                        // in directories with thousands of items.
                        const cols = Math.max(1, Math.floor(grid.width / grid.cellWidth))
                        const topRow = Math.max(0,
                            Math.floor((top + grid.contentY) / grid.cellHeight) - 2)
                        const bottomRow = Math.max(topRow,
                            Math.ceil((bottom + grid.contentY) / grid.cellHeight) + 2)
                        for (let i = topRow * cols;
                             i < Math.min(grid.count, (bottomRow + 1) * cols); i++) {
                            // itemAtIndex is null for offscreen delegates.
                            const item = grid.itemAtIndex(i)
                            if (!item) continue
                            const p = item.mapToItem(grid, 0, 0)
                            if (p.x < right && p.x + item.width > left
                                && p.y < bottom && p.y + item.height > top)
                                paths.push(files.entries[i].path)
                        }
                        return paths
                    }
                    function applyRectangle(x, y) {
                        lastX = Math.max(0, Math.min(grid.width, x))
                        lastY = Math.max(0, Math.min(grid.height, y))
                        const hits = selectionBetween(startX, startY, lastX, lastY)
                        let paths
                        if (modifiers & Qt.ControlModifier) {
                            paths = originalPaths.filter((p) => !hits.includes(p))
                                .concat(hits.filter((p) => !originalPaths.includes(p)))
                        } else if (modifiers & Qt.ShiftModifier) {
                            paths = originalPaths.concat(hits.filter((p) => !originalPaths.includes(p)))
                        } else {
                            paths = hits
                        }
                        const previous = files.selectedPaths
                        if (previous.length !== paths.length
                            || paths.some((p, i) => p !== previous[i]))
                            files.setSelection(paths, paths[paths.length - 1] ?? "")
                    }
                    onPressed: (mouse) => {
                        startX = mouse.x; startY = mouse.y
                        lastX = startX; lastY = startY
                        modifiers = mouse.modifiers
                        originalPaths = files.selectedPaths.slice()
                        dragging = false
                        hadDrag = false
                        files.forceActiveFocus()
                    }
                    onPositionChanged: (mouse) => {
                        if (!pressed) return
                        if (!dragging && Math.hypot(mouse.x - startX, mouse.y - startY) > 6) {
                            dragging = true
                            hadDrag = true
                        }
                        if (dragging) applyRectangle(mouse.x, mouse.y)
                    }
                    onReleased: {
                        if (dragging) files.selectionAnchor = files.selectedPath
                        dragging = false
                    }
                    onCanceled: { dragging = false; hadDrag = false }
                    onClicked: (mouse) => {
                        if (!hadDrag && !(mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)))
                            files.clearSelection()
                    }
                }

                Rectangle {
                    id: marqueeHighlight
                    objectName: "filesMarqueeHighlight"
                    z: 12
                    enabled: false
                    visible: marqueeBackground.dragging && grid.activeView
                    x: Math.min(marqueeBackground.startX, marqueeBackground.lastX)
                    y: Math.min(marqueeBackground.startY, marqueeBackground.lastY)
                    width: Math.abs(marqueeBackground.lastX - marqueeBackground.startX)
                    height: Math.abs(marqueeBackground.lastY - marqueeBackground.startY)
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, Theme.dark ? 0.19 : 0.12)
                    border.width: 1
                    border.color: Theme.accent
                    radius: 3
                }

                delegate: Item {
                    id: cell
                    required property var modelData
                    width: grid.cellWidth
                    height: grid.cellHeight
                    objectName: "fileCell:" + modelData.name
                    readonly property bool selected: files.selectedPaths.includes(modelData.path) || cellDrop.containsDrag
                    Accessible.role: Accessible.ListItem
                    Accessible.name: modelData.name
                    Accessible.selected: selected
                    opacity: files.cutPaths.includes(modelData.path) ? 0.5 : 1

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
                            font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: cell.selected ? Font.DemiBold : Font.Normal }
                        }
                        Text {
                            visible: !!cell.modelData.detail
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: cell.modelData.detail ?? ""
                            color: Theme.secondaryLabel
                            font { family: Theme.fontUi; pixelSize: Theme.fs(10) }
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
                        onPressed: (mouse) => { if (mouse.button === Qt.LeftButton && (!files.selectedPaths.includes(cell.modelData.path) || (mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)))) files.select(cell.modelData, mouse.modifiers) }
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.RightButton) files.itemMenu(cell, mouse.x, mouse.y, cell.modelData)
                            else if (!(mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier))) files.select(cell.modelData)
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
            Scroller { objectName: "filesGridScroller"; flickable: grid }

            ListView {
                id: list
                objectName: "filesListView"
                readonly property bool activeView: files.view === "list" && !files.loading && !files.error
                opacity: activeView ? 1 : 0
                visible: opacity > 0.001
                enabled: activeView
                Behavior on opacity {
                    NumberAnimation { duration: Theme.reduceMotion ? 0 : 125; easing.type: Easing.OutCubic }
                }
                anchors { fill: parent; margins: 16; topMargin: 0; bottomMargin: (pathBar.visible ? pathBar.height : 0) + (transferPanel.visible ? transferPanel.height : 0) + 4 }
                topMargin: win.toolbarHeight + 30
                spacing: 1
                model: files.entries

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    width: list.width
                    height: 36
                    radius: 7
                    objectName: "fileRow:" + modelData.name
                    readonly property bool selected: files.selectedPaths.includes(modelData.path) || rowDrop.containsDrag
                    Accessible.role: Accessible.ListItem
                    Accessible.name: modelData.name
                    Accessible.selected: selected
                    opacity: files.cutPaths.includes(modelData.path) ? 0.5 : 1
                    color: selected
                        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                        : rowHover.hovered
                            ? (Theme.dark ? "#0dffffff" : "#07000000")
                            : "transparent"
                    Behavior on color {
                        ColorAnimation { duration: Theme.reduceMotion ? 0 : 95; easing.type: Easing.OutCubic }
                    }

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
                        width: Math.max(40, parent.width * 0.55 - 48)
                        text: row.modelData.name
                        elide: Text.ElideRight
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: row.selected ? Font.DemiBold : Font.Normal }
                    }

                    Text {
                        x: parent.width * 0.55 + 8
                        width: Math.max(40, parent.width * 0.27 - 12)
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideMiddle
                        text: files.inTrash && row.modelData.origin
                            ? row.modelData.origin.replace(/\/[^/]+$/, "").replace(files.home, "~")
                            : new Date(row.modelData.modified * 1000).toLocaleDateString(Qt.locale(), Locale.ShortFormat)
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                    }

                    Text {
                        id: sizeText
                        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        width: Math.max(32, parent.width * 0.18 - 12)
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignRight
                        text: row.modelData.folder ? "Folder" : files.formatSize(row.modelData.size)
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                    }

                    HoverHandler { id: rowHover }
                    DragSource { id: rowDrag; entry: row.modelData; area: rowArea }
                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        drag.target: files.inTrash ? null : rowDrag
                        drag.threshold: 6
                        onPressed: (mouse) => { if (mouse.button === Qt.LeftButton && (!files.selectedPaths.includes(row.modelData.path) || (mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)))) files.select(row.modelData, mouse.modifiers) }
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.RightButton) files.itemMenu(row, mouse.x, mouse.y, row.modelData)
                            else if (!(mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier))) files.select(row.modelData)
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
            Scroller { objectName: "filesListScroller"; flickable: list }

            Row {
                visible: list.visible
                enabled: list.activeView
                opacity: list.opacity
                x: 16; y: win.toolbarHeight + 3; width: parent.width - 32
                component SortHeading: Item {
                    property string label
                    property string key
                    height: 24
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: "Sort by " + label
                    function sort() { if (files.sortKey === key) files.descending = !files.descending; else files.sortKey = key }
                    Keys.onReturnPressed: sort()
                    Keys.onSpacePressed: sort()
                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        color: sortArea.pressed
                            ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                            : sortArea.containsMouse ? Theme.fill : "transparent"
                        Behavior on color {
                            ColorAnimation { duration: Theme.reduceMotion ? 0 : 110 }
                        }
                    }
                    Text {
                        anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                        width: parent.width - 16
                        elide: Text.ElideRight
                        text: parent.label + (files.sortKey === parent.key ? files.descending ? " ↓" : " ↑" : "")
                        color: files.sortKey === parent.key ? Theme.label : Theme.secondaryLabel
                        font.pixelSize: Theme.fs(11)
                    }
                    MouseArea {
                        id: sortArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { parent.forceActiveFocus(); parent.sort() }
                    }
                    FocusRing {}
                }
                SortHeading { label: "Name"; key: "name"; width: parent.width * 0.55 }
                SortHeading { label: "Date Modified"; key: "modified"; width: parent.width * 0.27 }
                SortHeading { label: "Size"; key: "size"; width: parent.width * 0.18 }
            }

            Rectangle {
                id: transferPanel
                objectName: "filesTransferPanel"
                visible: transferProc.running || files.transferResult !== null
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: pathBar.visible ? pathBar.height : 0 }
                height: transferContent.height + 20
                color: Theme.windowBg
                Rectangle { width: parent.width; height: 1; color: Theme.separator }
                Column {
                    id: transferContent
                    x: 14; y: 10; width: parent.width - 28; spacing: 7
                    Text {
                        width: parent.width; elide: Text.ElideMiddle
                        text: files.transferResult ? (files.transferResult.cancelled ? "Transfer Cancelled" : files.transferResult.ok ? "Transfer Complete" : "Transfer Finished with Errors")
                            : files.cancelRequested ? "Cancelling…" : files.conflict ? "Waiting for a name-conflict choice…" : files.transferState.event === "preparing" ? "Preparing transfer…" : "Transferring “" + (files.transferState.name ?? "items") + "”…"
                        color: Theme.label; font { pixelSize: Theme.fs(13); weight: Font.DemiBold }
                    }
                    ProgressBar {
                        width: parent.width; visible: !files.transferResult
                        indeterminate: files.transferState.event === "preparing" || !files.transferState.total
                        value: Math.min(1, Math.max(((files.transferState.completed ?? 0) + (files.transferState.skipped ?? 0)) / Math.max(1, files.transferState.total ?? 1),
                            (files.transferState.totalBytes ?? 0) > 0 ? (files.transferState.bytes ?? 0) / files.transferState.totalBytes : 0))
                    }
                    Text {
                        width: parent.width; wrapMode: Text.WordWrap
                        text: files.transferResult ? (files.transferResult.completed?.length ?? 0) + " completed · " + (files.transferResult.skipped?.length ?? 0) + " skipped · " + (files.transferResult.errors?.length ?? 0) + " failed"
                            : (files.transferState.completed ?? 0) + " of " + (files.transferState.total ?? files.transferRequest.paths?.length ?? 0) + " items completed"
                                + ((files.transferState.totalBytes ?? 0) > 0 ? " · " + files.formatSize(files.transferState.bytes ?? 0) + " copied" : "")
                        color: Theme.secondaryLabel; font.pixelSize: Theme.fs(11)
                    }
                    Text {
                        visible: !!files.transferResult?.errors?.length
                        width: parent.width; wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight
                        text: files.transferResult?.errors?.[0]?.error ?? ""
                        color: Theme.dark ? "#ff453a" : "#d70015"; font.pixelSize: Theme.fs(12)
                    }
                    Row {
                        spacing: 8
                        Button { text: files.cancelRequested ? "Cancelling…" : "Cancel"; visible: transferProc.running && !files.transferResult; enabled: !files.cancelRequested; onClicked: files.cancelTransfer() }
                        Button {
                            text: "Show Results"; visible: !!files.transferResult?.completed?.length
                            onClicked: {
                                const paths = files.transferResult.completed.map((e) => e.path)
                                const dest = files.transferResult.destination || paths[0].replace(/\/[^/]+$/, "") || "/"
                                files.selectionAfterReload = paths; files.navigate(dest)
                            }
                        }
                        Button { text: "Dismiss"; visible: !!files.transferResult; enabled: !transferProc.running; onClicked: files.transferResult = null }
                    }
                }
            }

            Rectangle {
                id: conflictOverlay
                objectName: "filesConflict"
                parent: win.overlay; anchors.fill: parent; z: 120
                visible: !!files.conflict
                color: "#66000000"
                onVisibleChanged: if (visible) Qt.callLater(() => keepBoth.forceActiveFocus()); else files.forceActiveFocus()
                Keys.onEscapePressed: files.cancelTransfer()
                MouseArea { anchors.fill: parent }
                Rectangle {
                    anchors.centerIn: parent; width: Math.min(480, parent.width - 40); height: conflictColumn.height + 40
                    radius: 16; color: Theme.windowBg
                    Column {
                        id: conflictColumn
                        x: 20; y: 20; width: parent.width - 40; spacing: 14
                        Text { width: parent.width; wrapMode: Text.WordWrap; text: "“" + (files.conflict?.name ?? "") + "” already exists"; color: Theme.label; font { pixelSize: Theme.fs(16); weight: Font.DemiBold } }
                        Text { width: parent.width; wrapMode: Text.WordWrap; text: "Keep both items with different names, skip this item, or cancel the remaining transfer. Completed items will be kept."; color: Theme.secondaryLabel; font.pixelSize: Theme.fs(13) }
                        Checkbox { id: conflictAll; width: parent.width; text: "Use this choice for all name conflicts"; KeyNavigation.tab: cancelConflict; KeyNavigation.backtab: keepBoth }
                        Row {
                            spacing: 8
                            Button { id: cancelConflict; text: "Cancel Transfer"; KeyNavigation.tab: skipConflict; KeyNavigation.backtab: conflictAll; onClicked: files.cancelTransfer() }
                            Button { id: skipConflict; text: "Skip"; KeyNavigation.tab: keepBoth; KeyNavigation.backtab: cancelConflict; onClicked: files.answerConflict("skip") }
                            Button { id: keepBoth; objectName: "filesKeepBoth"; text: "Keep Both"; prominent: true; KeyNavigation.tab: conflictAll; KeyNavigation.backtab: skipConflict; onClicked: files.answerConflict("keep-both") }
                        }
                    }
                }
            }

            ModalSheet {
                id: infoDialog
                objectName: "filesInfo"
                parent: win.overlay
                panelWidth: 460
                panelHeight: infoContent.implicitHeight + 40
                z: 110
                property bool pathCopied: false
                Timer { id: copiedPathReset; interval: 1400; onTriggered: infoDialog.pathCopied = false }
                function copyPath() {
                    const location = files.info.path ?? ""
                    if (!location) return
                    Quickshell.clipboardText = location
                    pathCopied = true
                    copiedPathReset.restart()
                }
                // The old Get Info card had no backdrop hit barrier and
                // could leak clicks to Finder underneath while it was open.
                onShownChanged: {
                    copiedPathReset.stop()
                    pathCopied = false
                    if (shown) Qt.callLater(() => {
                        if (infoDialog.shown) infoClose.forceActiveFocus()
                    })
                }
                onClosed: files.forceActiveFocus()
                Column {
                    id: infoContent
                    width: parent.width
                    spacing: 12
                    Text { width: parent.width; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideMiddle; text: (files.info.name ?? "") + " Info"; color: Theme.label; font { pixelSize: Theme.fs(17); weight: Font.DemiBold } }
                    Flickable {
                        id: infoScroll
                        activeFocusOnTab: true
                        Keys.onDownPressed: contentY = Math.min(Math.max(0, contentHeight - height), contentY + 30)
                        Keys.onUpPressed: contentY = Math.max(0, contentY - 30)
                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_PageDown) contentY = Math.min(Math.max(0, contentHeight - height), contentY + height)
                            else if (event.key === Qt.Key_PageUp) contentY = Math.max(0, contentY - height)
                            else return
                            event.accepted = true
                        }
                        width: parent.width; height: Math.min(infoText.implicitHeight, Math.max(70, infoDialog.parent.height - 240))
                        contentHeight: infoText.height; clip: true; boundsBehavior: Flickable.StopAtBounds
                        Text { id: infoText; width: infoScroll.width - 12; wrapMode: Text.WrapAnywhere; text: "Kind: " + (files.info.mime ?? "") + "\nSize: " + (files.info.folder ? "Folder (contents not counted)" : files.formatSize(files.info.size ?? 0)) + "\nWhere: " + (files.info.location ?? "") + "\nModified: " + new Date((files.info.modified ?? 0) * 1000).toLocaleString() + "\nPermissions: " + (files.info.permissions ?? "") + (files.info.link ? "\nLink target: " + files.info.link : ""); color: Theme.label; font.pixelSize: Theme.fs(13) }
                        Scroller { parent: infoScroll; flickable: infoScroll }
                    }
                    Row {
                        spacing: 8
                        Button {
                            objectName: "filesCopyPath"
                            text: infoDialog.pathCopied ? "Copied" : "Copy Path"
                            onClicked: infoDialog.copyPath()
                        }
                        Button { id: infoClose; text: "Done"; prominent: true; onClicked: infoDialog.close() }
                    }
                }
            }

            // The path bar and status bar, as Finder's: the disk and the folders
            // down to this one (each opens on a click), the items and the room left.
            Rectangle {
                id: pathBar
                objectName: "filesPathBar"
                // Keep the breadcrumb bar mounted while switching folders.
                // Hiding it during the asynchronous listing made the content
                // jump by 28px and stole keyboard focus from the clicked crumb.
                visible: !files.special
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 28
                color: Theme.contentBg
                Rectangle { width: parent.width; height: 1; color: Theme.separator }
                Item {
                    id: crumbBox
                    anchors { left: parent.left; leftMargin: 10; right: status.left; rightMargin: 12; top: parent.top; bottom: parent.bottom }
                    clip: true
                    // A deep folder doesn't crop names: the disk and this folder
                    // stay, with as many folders before it as fit, and the rest
                    // fold into "…", whose menu opens any of them. A very long
                    // name is shortened in the middle, as in Finder: this
                    // folder's to half the bar, any other's to 160 px.
                    FontMetrics { id: crumbMetrics; font { family: Theme.fontUi; pixelSize: Theme.fs(11) } }
                    function nameLimit(i) { return i === files.crumbs.length - 1 ? Math.max(80, width / 2) : Math.min(160, Math.max(60, width / 4)) }
                    function nameWidth(c, i) { return Math.min(crumbMetrics.advanceWidth(c.name), nameLimit(i)) }
                    function crumbWidth(c, i) { return nameWidth(c, i) + 12 + 4 + 10 + 1 + (i > 0 ? 12 : 0) }
                    readonly property var shown: {
                        const cs = files.crumbs
                        const all = cs.map((c, i) => ({ c: c, i: i }))
                        if (cs.length < 3 || cs.reduce((a, c, i) => a + crumbWidth(c, i), 0) <= width) return all
                        let used = crumbWidth(cs[0], 0) + 34 + crumbWidth(cs[cs.length - 1], 1)
                        let start = cs.length - 1
                        while (start - 1 > 0 && used + crumbWidth(cs[start - 1], 1) <= width) used += crumbWidth(cs[--start], 1)
                        if (start === 1) return all
                        return [all[0], { folded: cs.slice(1, start), i: 1 }].concat(all.slice(start))
                    }
                    Row {
                        id: crumbRow
                        objectName: "filesCrumbs"
                        anchors.verticalCenter: parent.verticalCenter
                        // Still too long (one very long name): keep the end in view.
                        x: Math.min(0, parent.width - implicitWidth)
                        spacing: 1
                        Repeater {
                            model: crumbBox.shown
                            delegate: Row {
                                id: crumb
                                required property var modelData
                                readonly property int index: modelData.i
                                readonly property var folded: modelData.folded ?? null
                                readonly property var c: modelData.c ?? ({ name: "…", path: "", kind: "" })
                                spacing: 1
                                Symbol {
                                    visible: crumb.index > 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "chevron-small-right"; size: 11; tone: "gray"
                                }
                                Item {
                                    id: crumbButton
                                    objectName: crumb.folded ? "filesCrumbsFolded" : "filesCrumb:" + crumb.c.path
                                    width: crumbContent.implicitWidth + 10; height: 22
                                    anchors.verticalCenter: parent.verticalCenter
                                    activeFocusOnTab: true
                                    function activate() {
                                        if (crumb.folded)
                                            menu.popup(crumbButton, 0, -6 - crumb.folded.length * 26,
                                                crumb.folded.map((f) => ({ text: f.name, action: () => files.navigate(f.path) })))
                                        else files.navigate(crumb.c.path)
                                    }
                                    Accessible.role: crumb.folded ? Accessible.ButtonMenu : Accessible.Button
                                    Accessible.name: crumb.folded ? crumb.folded.map((f) => f.name).join(", ") : crumb.c.name
                                    Accessible.onPressAction: crumbButton.activate()
                                    Keys.onReturnPressed: crumbButton.activate()
                                    Keys.onSpacePressed: (event) => {
                                        if (!event.isAutoRepeat) crumbButton.activate()
                                    }
                                    FocusRing {}
                                    Rectangle {
                                        anchors.fill: parent; radius: 6
                                        color: crumbArea.pressed ? Theme.selection : crumbArea.containsMouse
                                            ? (Theme.dark ? "#12ffffff" : "#0a000000") : "transparent"
                                        scale: !Theme.reduceMotion && crumbArea.pressed ? 0.97 : 1
                                        Behavior on scale {
                                            enabled: !Theme.reduceMotion
                                            NumberAnimation { duration: 95; easing.type: Easing.OutCubic }
                                        }
                                        Behavior on color {
                                            ColorAnimation { duration: Theme.reduceMotion ? 0 : 100; easing.type: Easing.OutCubic }
                                        }
                                    }
                                    Row {
                                        id: crumbContent
                                        anchors.centerIn: parent
                                        spacing: 4
                                        Symbol { visible: !crumb.folded; anchors.verticalCenter: parent.verticalCenter; name: crumb.c.kind; size: 12; tone: crumb.c.kind === "folder" ? "accent" : "gray" }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: crumb.c.name
                                            width: crumb.folded ? implicitWidth : Math.min(implicitWidth, crumbBox.nameLimit(crumb.index))
                                            elide: Text.ElideMiddle
                                            color: !crumb.folded && crumb.index === files.crumbs.length - 1 ? Theme.label : Theme.secondaryLabel
                                            font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                                        }
                                    }
                                    MouseArea {
                                        id: crumbArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            crumbButton.forceActiveFocus()
                                            crumbButton.activate()
                                        }
                                    }
                                    DropArea {
                                        anchors.fill: parent
                                        enabled: !crumb.folded
                                        onEntered: (drag) => drag.accepted = files.accepts(drag, crumb.c.path)
                                        onDropped: (drop) => files.dropOn(drop, crumb.c.path)
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
                    text: files.notice || (files.busy && !transferProc.running ? "Working…" : (files.selectedPaths.length ? files.selectedPaths.length + " of " : "") + files.entries.length + (files.entries.length === 1 ? " item" : " items")
                        + (files.free >= 0 ? ", " + files.formatSize(files.free) + " available" : ""))
                    color: files.notice ? Theme.label : Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: Theme.fs(11); weight: files.notice ? Font.Medium : Font.Normal }
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

            // Small, passive keyboard-search cue: visible for one short beat,
            // with no search panel and no changes to the actual folder query.
            Rectangle {
                id: typeAheadCue
                objectName: "filesTypeAheadCue"
                parent: win.overlay
                anchors { right: parent.right; rightMargin: 22; bottom: parent.bottom; bottomMargin: 40 }
                z: 85
                enabled: false
                width: Math.min(Math.max(100, cueLabel.implicitWidth + 24), Math.max(0, parent.width - 44))
                height: 34
                radius: 13
                color: Theme.windowBg
                border { width: 1; color: Theme.separator }
                opacity: files.typeAhead ? 1 : 0
                visible: opacity > 0.001
                Behavior on opacity {
                    NumberAnimation { duration: Theme.reduceMotion ? 0 : 120; easing.type: Easing.OutCubic }
                }
                Text {
                    id: cueLabel
                    anchors.centerIn: parent
                    text: "Jump to  " + files.typeAhead
                    color: Theme.label
                    elide: Text.ElideRight
                    width: Math.max(0, parent.width - 24)
                    horizontalAlignment: Text.AlignHCenter
                    font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: Font.Medium }
                }
            }

            // Empty Trash asks first, as on the Mac.
            ModalSheet {
                id: confirmEmpty
                objectName: "filesEmptyTrashSheet"
                parent: win.overlay
                panelWidth: 300
                panelHeight: confirmColumn.implicitHeight + 40
                z: 110
                onShownChanged: if (shown) Qt.callLater(() => {
                    if (confirmEmpty.shown) emptyButton.forceActiveFocus()
                })
                onClosed: files.forceActiveFocus()
                Keys.onEscapePressed: confirmEmpty.close()
                Column {
                    id: confirmColumn
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    spacing: 10
                    Symbol { anchors.horizontalCenter: parent.horizontalCenter; name: "trash"; size: 34; tone: "auto" }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: "Are you sure you want to permanently erase the items in the Trash?"
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.Bold }
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: "You can’t undo this action."
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                    }
                    Item { width: 1; height: 4 }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8
                        Button { width: 122; text: "Cancel"; onClicked: confirmEmpty.close() }
                        Button {
                            id: emptyButton
                            width: 122
                            text: "Empty Trash"
                            prominent: true
                            destructive: true
                            onClicked: { confirmEmpty.close(); files.runOperation(["empty-trash"], "empty-trash") }
                        }
                    }
                }
            }

            QuickLook {
                id: quickLook
                parent: win.overlay
                entry: files.selectedEntry
                onOpenRequested: (entry) => { open = false; files.openEntry(entry) }
                onNavigateRequested: (delta) => {
                    files.moveSelection(delta, 0)
                    // moveSelection deliberately focuses Files for normal arrow
                    // browsing; Quick Look's own arrow loop stays in front.
                    quickLook.focusPreview()
                }
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

            ModalSheet {
                id: editDialog
                objectName: "filesEditSheet"
                parent: win.overlay
                panelWidth: 380
                panelHeight: 150
                z: 110
                onClosed: files.forceActiveFocus()

                Column {
                    anchors.fill: parent
                    spacing: 12

                    Text {
                        text: files.dialogMode === "rename" ? "Rename" : "New Folder"
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: Theme.fs(17); weight: Font.DemiBold }
                    }

                    TextField {
                        id: dialogField
                        width: parent.width
                        text: files.dialogText
                        placeholder: "Name"
                        onAccepted: files.submitDialog()
                        input.Keys.onEscapePressed: editDialog.close()
                    }

                    Row {
                        anchors.right: parent.right
                        spacing: 8
                        Button { text: "Cancel"; onClicked: editDialog.close() }
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
