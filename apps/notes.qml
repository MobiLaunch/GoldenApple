//@ pragma AppId org.goldengate.Notes
// Notes, laid out like Notes on macOS 27: folders in a floating glass sidebar,
// the notes of a folder grouped by date, and the note itself, with the
// toolbar over each column.
//
// Notes are Markdown files: ~/Documents/Notes/<Folder>/<Title>.md
// (GG_NOTES_DIR to change it), so they open in any editor and sync with any
// file sync. The first line is the title; the file is renamed to follow it.
// Deleted notes go to "Recently Deleted" first.
import Quickshell
import Quickshell.Io
import QtQuick
import "lib"
import "lib/theme"
import "notes"
import "notes/md.js" as Md

ShellRoot {
    AppWindow {
        id: win
        // Closing puts the window away (Notes keeps running, as on the Mac);
        // quitting ends it. Either saves the note being written first, and a
        // save that fails keeps the window open.
        documentApp: true
        function whenSaved(then) {
            if (editor.flush()) then()
            else if (!editor.saveError) editor.afterRename = then         // once the rename lands
        }
        closeAction: () => whenSaved(() => win.putAway())
        quitAction: () => whenSaved(() => Qt.quit())
        title: "Notes"
        implicitWidth: Math.min(1120, (Quickshell.screens[0]?.width ?? 1280) - 80)
        implicitHeight: Math.min(720, (Quickshell.screens[0]?.height ?? 900) - 150)
        minimumSize: Qt.size(720, 420)
        sidebarWidth: app.sidebarOpen ? (win.tabletCompact ? Math.min(245, win.width * 0.42) : 220) : 0
        fullSizeContent: true
        background: Theme.contentBg

        // ---------------------------------------------------------------- toolbar
        toolbarSidebar: [
            ToolbarButton { round: true; symbol: "folder"; onClicked: app.newFolder() },
            ToolbarButton { round: true; symbol: "sidebar"; checked: app.sidebarOpen; onClicked: app.sidebarOpen = !app.sidebarOpen }
        ]
        toolbarItems: [
            // Over the list: the folder and how many notes it has.
            Column {
                // Past the traffic lights and sidebar buttons while the sidebar is hidden.
                x: Math.max(win.sidebarWidth > 0 ? app.listX + 16 : 176,
                    win.toolbarLeadingEnd)
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    text: app.folderTitle
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.Bold }
                }
                Text {
                    text: app.visibleNotes.length + (app.visibleNotes.length === 1 ? " note" : " notes")
                    color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                }
            },
            ToolbarButton {
                id: listMore
                x: app.listX + app.listWidth - width - 10
                anchors.verticalCenter: parent.verticalCenter
                round: true; symbol: "ellipsis"
                onClicked: listMenu.popup(listMore, 0, height + 6, [
                    { text: "Sort by Date Edited", checked: app.sortBy === "date", action: () => app.sortBy = "date" },
                    { text: "Sort by Title", checked: app.sortBy === "title", action: () => app.sortBy = "title" },
                    { separator: true },
                    { text: "Show Folder in Files", action: () => Quickshell.execDetached(["xdg-open", app.folder || app.root]) },
                ])
            },
            // Over the note: new note, formatting; more and search on the right.
            ToolbarButton {
                x: app.editorX + 12
                anchors.verticalCenter: parent.verticalCenter
                round: true; symbol: "compose"
                onClicked: app.newNote()
            },
            ToolbarPill {
                x: app.editorX + 58
                anchors.verticalCenter: parent.verticalCenter
                visible: app.editorWidth > 360
                ToolbarButton { id: formatBtn; text: "Aa"; enabled: !!app.current; onClicked: editor.formatMenu(formatBtn) }
                ToolbarButton { symbol: "checkmark"; enabled: !!app.current; onClicked: editor.setStyle("check") }
                ToolbarButton { symbol: "list"; enabled: !!app.current; onClicked: editor.setStyle("bullet") }
            },
            ToolbarButton {
                id: noteMore
                x: parent.width - width - (searchBox.visible ? searchBox.width + 20 : 58)
                anchors.verticalCenter: parent.verticalCenter
                round: true; symbol: "ellipsis"
                enabled: !!app.current
                onClicked: listMenu.popup(noteMore, 0, height + 6, [
                    app.inTrash(app.current) ? { text: "Recover Note", action: () => app.recoverNote(app.current) } : null,
                    { text: app.inTrash(app.current) ? "Delete Immediately" : "Delete Note", action: () => app.deleteNote(app.current) },
                    { text: "Copy as Markdown", action: () => Quickshell.clipboardText = editor.markdown() },
                    { separator: true },
                    { text: "Show in Files", action: () => Quickshell.execDetached(["gg-files", "--select", app.current]) },
                ].filter((i) => i))
            },
            ToolbarButton {
                x: parent.width - width - 12
                anchors.verticalCenter: parent.verticalCenter
                visible: !searchBox.visible
                round: true; symbol: "search"
                onClicked: { searchBox.visible = true; searchBox.input.forceActiveFocus() }
            },
            TextField {
                id: searchBox
                visible: false
                x: parent.width - width - 12
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(220, app.editorWidth - 160)
                height: 32
                search: true
                placeholder: "Search"
                onTextChanged: app.search(text)
                input.Keys.onEscapePressed: { text = ""; visible = false }
            }
        ]

        // ---------------------------------------------------------------- folders
        sidebar: [
            Column {
                width: parent.width
                Text {
                    leftPadding: 10; topPadding: 6; bottomPadding: 4
                    text: "On My Computer"
                    color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: Theme.fs(11); weight: Font.DemiBold }
                }
                Repeater {
                    model: [{ name: "All Notes", path: "", symbol: "doc" }].concat(
                        app.folders.filter((f) => f.name !== app.trashName).map((f) => ({ name: f.name, path: f.path, symbol: "folder" })),
                        app.folders.some((f) => f.name === app.trashName) ? [{ name: app.trashName, path: app.root + "/" + app.trashName, symbol: "trash" }] : [])
                    delegate: Item {
                        id: folderRow
                        required property var modelData
                        width: parent.width; height: 30
                        readonly property bool selected: app.folder === modelData.path
                        readonly property int count: modelData.path ? app.notes.filter((n) => n.folderPath === modelData.path).length
                                                                    : app.notes.filter((n) => n.folder !== app.trashName).length
                        Rectangle {
                            anchors.fill: parent; radius: 8
                            color: Theme.dark ? "#ffffff" : "#000000"
                            opacity: folderRow.selected ? (Theme.dark ? 0.12 : 0.07) : fh.hovered ? 0.04 : 0
                        }
                        Symbol { x: 10; anchors.verticalCenter: parent.verticalCenter; name: folderRow.modelData.symbol; tone: "accent"; size: 16 }
                        Text {
                            x: 36; anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 70; elide: Text.ElideRight
                            text: folderRow.modelData.name
                            color: Theme.label
                            font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: folderRow.selected ? Font.DemiBold : Font.Normal }
                        }
                        Text {
                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            text: folderRow.count
                            color: Theme.secondaryLabel
                            font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
                        }
                        HoverHandler { id: fh }
                        TapHandler { onTapped: app.folder = folderRow.modelData.path }
                    }
                }
                // Naming a new folder
                TextField {
                    id: folderName
                    visible: app.namingFolder
                    width: parent.width
                    height: 30
                    placeholder: "New Folder"
                    onAccepted: app.createFolder(text)
                    input.Keys.onEscapePressed: app.namingFolder = false
                    Connections {
                        target: folderName.input
                        function onActiveFocusChanged() {
                            if (!folderName.input.activeFocus && app.namingFolder)
                                app.createFolder(folderName.text)
                        }
                    }
                }
            }
        ]

        Item {
            id: app
            anchors.fill: parent

            readonly property string root: Quickshell.env("GG_NOTES_DIR") || (Quickshell.env("HOME") + "/Documents/Notes")
            readonly property string trashName: "Recently Deleted"
            property bool sidebarOpen: true
            property var folders: []        // {name, path}
            property var notes: []          // {folder, folderPath, path, mtime, title, preview}
            property string folder: root + "/Notes"   // "" = all notes
            property string current: ""
            property string sortBy: "date"
            property var matches: null      // paths matching the search, or null
            property bool namingFolder: false

            // Columns. listX and editorX are in window coordinates (the toolbar's);
            // inside this item the list starts at 0.
            readonly property real listX: win.contentX
            readonly property real listWidth: Math.max(250, Math.min(320, width * 0.3))
            readonly property real editorX: listX + listWidth
            readonly property real editorWidth: width - listWidth

            readonly property string folderTitle: folder === "" ? "All Notes" : folder.split("/").pop()
            readonly property var visibleNotes: {
                let ns = notes.filter((n) => folder === "" ? n.folder !== trashName : n.folderPath === folder)
                if (matches) ns = notes.filter((n) => matches.includes(n.path))
                return ns.slice().sort((a, b) => sortBy === "title" ? a.title.localeCompare(b.title) : b.mtime - a.mtime)
            }

            function refresh() { lister.running = true }
            function newNote() {
                if (!editor.flush()) return
                const dir = folder && !folder.endsWith("/" + trashName) ? folder : root + "/Notes"
                let name = "New Note.md", i = 2
                while (notes.some((n) => n.path === dir + "/" + name)) name = "New Note " + (i++) + ".md"
                const path = dir + "/" + name
                const n = { folder: dir.split("/").pop(), folderPath: dir, path: path, mtime: Date.now() / 1000, title: "New Note", preview: "", fresh: true }
                notes = [n].concat(notes)
                current = path
                editor.startNew(path)
            }
            function deleteNote(path) {
                if (!path) return
                const wasCurrent = path === app.current
                if (!editor.flush()) return
                if (wasCurrent) path = editor.loadedPath
                const inTrash = path.includes("/" + trashName + "/")
                const i = visibleNotes.findIndex((n) => n.path === path)
                const next = visibleNotes[i + 1] ?? visibleNotes[i - 1] ?? null
                // Never replaces a note already in Recently Deleted (see notes/trash.py).
                trashOp.go([inTrash ? "erase" : "delete", path])
                notes = notes.filter((n) => n.path !== path)
                current = next ? next.path : ""
            }
            function recoverNote(path) {
                if (!path || !editor.flush()) return
                trashOp.go(["recover", path])
                notes = notes.filter((n) => n.path !== path)
                if (current === path) current = ""
            }
            function inTrash(path) { return !!path && path.includes("/" + trashName + "/") }
            function newFolder() { sidebarOpen = true; namingFolder = true; folderName.text = "New Folder"; folderName.input.selectAll(); folderName.input.forceActiveFocus() }
            function createFolder(name) {
                namingFolder = false
                name = name.replace(/[\/\\]/g, "").trim()
                if (!name) return
                Quickshell.execDetached(["mkdir", "-p", root + "/" + name])
                folder = root + "/" + name
                refreshLater.restart()
            }
            function search(q) {
                if (!q.trim()) { matches = null; return }
                grep.query = q
                grep.running = false
                grep.running = true
            }
            // Called by the editor after a save: keep the list current.
            function saved(path, newPath, title, preview) {
                notes = notes.map((n) => n.path === path ? Object.assign({}, n, { path: newPath, title: title || "New Note", preview: preview, mtime: Date.now() / 1000, fresh: false }) : n)
                if (current === path) current = newPath
            }

            Timer { id: refreshLater; interval: 250; onTriggered: app.refresh() }
            Process {
                id: trashOp
                property var queue: []
                property string doing: ""
                function go(args) { queue = queue.concat([args]); if (!running && !doing) next() }
                function next() {
                    doing = ""
                    if (!queue.length) { refreshLater.restart(); return }
                    doing = queue[0][0]
                    command = ["python3", Qt.resolvedUrl("notes/trash.py").toString().replace("file://", ""), queue[0][0], app.root, queue[0][1]]
                    queue = queue.slice(1)
                    running = true
                }
                stdout: StdioCollector {
                    onStreamFinished: {
                        let r = null
                        try { r = JSON.parse(text) } catch (e) {}
                        if (r && r.ok && trashOp.doing === "recover") app.current = r.path
                    }
                }
                onExited: Qt.callLater(trashOp.next)
            }
            Process {
                id: lister
                running: true
                command: ["bash", Qt.resolvedUrl("notes/list.sh").toString().replace("file://", ""), app.root]
                stdout: StdioCollector {
                    onStreamFinished: {
                        const fs = [], ns = []
                        for (const line of text.split("\n")) {
                            const c = line.split("\t")
                            if (c[0] === "F") fs.push({ name: c[1], path: c[2] })
                            else if (c[0] === "N") ns.push({ folder: c[1], folderPath: c[2].replace(/\/[^/]+$/, ""), path: c[2], mtime: Number(c[3]), title: c[4] || "New Note", preview: c[5] ?? "" })
                        }
                        // Keep a new note that hasn't been saved yet.
                        const fresh = app.notes.filter((n) => n.fresh && !ns.some((m) => m.path === n.path))
                        app.folders = fs.sort((a, b) => a.name === "Notes" ? -1 : b.name === "Notes" ? 1 : a.name.localeCompare(b.name))
                        app.notes = fresh.concat(ns)
                        if (!app.current || !app.notes.some((n) => n.path === app.current))
                            app.current = app.visibleNotes[0]?.path ?? ""
                    }
                }
            }
            Process {
                id: grep
                property string query
                command: ["grep", "-rilF", "--include=*.md", "--", query, app.root]
                stdout: StdioCollector { onStreamFinished: app.matches = text.split("\n").filter((l) => l) }
            }
            // Pick up changes made outside the app.
            Timer { interval: 5000; running: true; repeat: true; onTriggered: if (!editor.dirty) app.refresh() }

            Keys.onPressed: (e) => {
                const ctrl = e.modifiers & Qt.ControlModifier
                if (ctrl && e.key === Qt.Key_N && !(e.modifiers & Qt.ShiftModifier)) { app.newNote(); e.accepted = true }
                else if (ctrl && (e.modifiers & Qt.ShiftModifier) && e.key === Qt.Key_N) { app.newFolder(); e.accepted = true }
                else if (ctrl && e.key === Qt.Key_F) { searchBox.visible = true; searchBox.input.forceActiveFocus(); e.accepted = true }
                else if (ctrl && e.key === Qt.Key_Backspace) { app.deleteNote(app.current); e.accepted = true }
            }

            // ------------------------------------------------------------ list
            NoteList {
                id: list
                x: 0; y: win.toolbarHeight
                width: app.listWidth; height: parent.height - y
                notes: app.visibleNotes
                current: app.current
                showFolder: app.folder === "" || !!app.matches
                onPicked: (path) => { if (editor.flush()) app.current = path }
                onMenu: (path, item, mx, my) => listMenu.popup(item, mx, my, (app.inTrash(path) ? [
                    { text: "Recover", action: () => app.recoverNote(path) },
                    { text: "Delete Immediately", action: () => app.deleteNote(path) },
                ] : [
                    { text: "Delete", action: () => app.deleteNote(path) },
                ]).concat([
                    { text: "Show in Files", action: () => Quickshell.execDetached(["gg-files", "--select", path]) },
                ]))
            }
            Rectangle { x: app.listWidth; width: 1; height: parent.height; color: Theme.separator }

            // ------------------------------------------------------------ editor
            NoteEditor {
                id: editor
                x: app.listWidth + 1; y: win.toolbarHeight
                width: app.editorWidth - 1; height: parent.height - y
                path: app.current
                mtime: app.notes.find((n) => n.path === app.current)?.mtime ?? 0
                taken: app.notes.map((n) => n.path)
                root: app.root
                onSaved: (path, newPath, title, preview) => app.saved(path, newPath, title, preview)
                onSaveFailed: app.current = editor.loadedPath
                onMenuRequested: (items, item, mx, my) => listMenu.popup(item, mx, my, items)
            }
            Text {
                anchors.centerIn: editor
                visible: !app.current
                text: app.notes.length ? "No Note Selected" : "No Notes"
                color: Theme.tertiaryLabel
                font { family: Theme.fontUi; pixelSize: Theme.fs(15); weight: Font.Medium }
            }
        }

        PopupMenu { id: listMenu; parent: win.overlay }
    }
}

