// The project window, laid out like Xcode on macOS 27.
//   toolbar:  sidebar ▸ Run/Stop ▸ scheme › destination ▸ activity view ▸ + ⋯ inspector
//   sidebar:  navigators (Project, Find, Issues, Reports)
//   content:  tabs, jump bar, editor, debug area
//   trailing: inspectors
import Quickshell
import QtQuick
import "../lib"
import "../lib/theme"
import "devices.js" as Devices

AppWindow {
    id: win
    property var app
    property var backend
    property bool navigatorOpen: true
    property bool inspectorOpen: true
    property bool debugOpen: true
    property real debugHeight: 210

    title: app.project ? app.project.name : "LCode"
    implicitWidth: Math.min(1480, (Quickshell.screens[0]?.width ?? 1600) - 60)
    implicitHeight: Math.min(920, (Quickshell.screens[0]?.height ?? 1000) - 100)
    minimumSize: Qt.size(940, 560)
    sidebarWidth: navigatorOpen ? 270 : 0
    trailingSidebarWidth: inspectorOpen ? 260 : 0
    background: Theme.contentBg
    closeAction: () => win.requestClose()

    // ------------------------------------------------------------ lifecycle
    Component.onCompleted: {
        app.beforeTask = (then) => editorArea.saveAll((ok) => { if (ok) then() })
        const st = app.project.state || {}
        for (const p of (st.open_files || [])) editorArea.open(p, 0, 0)
        // gg-lcode path/to/File.swift (like xed) opens the package at that file.
        const launched = Quickshell.env("LCODE_FILE") || ""
        if (launched) editorArea.open(launched, 0, 0)
        else if (st.selected_file) editorArea.open(st.selected_file, 0, 0)
        else if (!(st.open_files || []).length) openDefaultFile.start()
    }
    Timer {
        id: openDefaultFile
        interval: 300
        onTriggered: {
            const files = win.app.nodes.filter((n) => !n.dir)
            const pick = files.find((n) => n.name === "ContentView.swift" || n.name === "main.swift")
                || files.find((n) => n.name.endsWith(".swift"))
            if (pick) { navigator.reveal(pick.path); editorArea.open(pick.path, 0, 0) }
        }
    }

    function requestClose() {
        const finish = () => {
            win.app.saveState(editorArea.openFiles(), editorArea.currentIsFile ? editorArea.currentPath : "")
            win.app.stop()
            win.app.shutDownSimulator()
            Qt.callLater(Qt.quit)
        }
        if (!editorArea.hasUnsaved()) { finish(); return }
        confirm.ask("Do you want to save the changes to the open files?", "Your changes will be lost if you don't save them.",
            [{ text: "Don't Save", id: "discard", destructive: true }, { text: "Cancel", id: "cancel" }, { text: "Save All", id: "save", prominent: true }],
            (choice) => {
                if (choice === "save") editorArea.saveAll((ok) => { if (ok) finish() })
                else if (choice === "discard") finish()
            })
    }

    Connections {
        target: win.app
        function onRevealLocation(path, line, column) {
            win.navigatorOpen = true
            navigator.page = 2
            editorArea.open(path, line, column)
        }
        function onAlertRequested(title, message) { confirm.ask(title, message, [{ text: "OK", id: "ok", prominent: true }], null) }
        function onSchemeChanged() { win.app.saveState(editorArea.openFiles(), editorArea.currentIsFile ? editorArea.currentPath : "") }
    }

    // -------------------------------------------------------------- toolbar
    toolbarSidebar: [
        ToolbarButton {
            round: true
            symbol: "sidebar"
            checked: win.navigatorOpen
            Accessible.name: "Hide or show the Navigator (⌘0)"
            onClicked: win.navigatorOpen = !win.navigatorOpen
        }
    ]

    toolbarItems: [
        ToolbarPill {
            id: runPill
            x: Math.max(win.contentX + 12, 180)
            anchors.verticalCenter: parent.verticalCenter
            ToolbarButton {
                symbol: "play"
                enabled: !!win.app.project
                Accessible.name: "Run (⌘R)"
                onClicked: win.app.run()
            }
            ToolbarButton {
                symbol: "stop"
                symbolSize: 15
                enabled: win.app.busy
                Accessible.name: "Stop (⌘.)"
                onClicked: win.app.stop()
            }
        },
        ToolbarPill {
            id: schemePill
            x: runPill.x + runPill.width + 10
            anchors.verticalCenter: parent.verticalCenter
            ToolbarButton {
                id: schemeButton
                symbol: win.app.project && win.app.project.kind === "app" ? "smartphone" : win.app.project && win.app.project.kind === "library" ? "layers" : "terminal"
                symbolSize: 15
                text: win.app.schemeName
                onClicked: menu.popup(schemeButton, 0, schemeButton.height + 8,
                    [{ header: "Schemes" }].concat(
                        win.app.project.products.length
                            ? win.app.project.products.map((p) => ({ text: p, checked: p === win.app.scheme, action: () => win.app.scheme = p }))
                            : [{ text: "No Executable Products", enabled: false }],
                        [{ separator: true }, { text: "Edit Package.swift…", action: () => editorArea.open(win.app.project.root + "/Package.swift", 0, 0) }]))
            }
            Symbol {
                anchors.verticalCenter: parent.verticalCenter
                name: "chevron-small-right"
                size: 12
                tone: "gray"
            }
            ToolbarButton {
                id: destinationButton
                symbol: win.app.destination === "host" ? "window" : (Devices.byId(win.app.destination)?.tablet ? "tablet" : "smartphone")
                symbolSize: 15
                text: win.app.destinationName
                onClicked: menu.popup(destinationButton, 0, destinationButton.height + 8,
                    [{ header: "My Computer" },
                     { text: "My Linux PC", symbol: "window", checked: win.app.destination === "host", action: () => win.app.destination = "host" },
                     { header: "Simulators" }].concat(
                        Devices.DEVICES.map((d) => ({ text: d.name, symbol: d.tablet ? "tablet" : "smartphone", checked: win.app.destination === d.id,
                                                      action: () => win.app.destination = d.id }))))
            }
        },
        ActivityView {
            id: activity
            app: win.app
            readonly property real leftEdge: schemePill.x + schemePill.width + 14
            // Stop short of the toolbar's right-hand buttons (over the inspector when it's open).
            readonly property real rightEdge: win.inspectorOpen ? win.contentX + win.contentWidth - 12 : win.width - 150
            width: Math.max(220, Math.min(560, rightEdge - leftEdge))
            x: Math.max(leftEdge, (leftEdge + rightEdge - width) / 2)
            anchors.verticalCenter: parent.verticalCenter
            visible: rightEdge - leftEdge > 220
            onIssuesClicked: { win.navigatorOpen = true; navigator.page = 2 }
        }
    ]

    toolbarRight: [
        ToolbarButton {
            id: addButton
            round: true
            symbol: "plus"
            Accessible.name: "New File (⌘N)"
            onClicked: win.promptNewItem(win.newItemFolder(), false)
        },
        ToolbarButton {
            id: moreButton
            round: true
            symbol: "ellipsis"
            Accessible.name: "Product and View menus"
            onClicked: menu.popup(moreButton, moreButton.width - 240, moreButton.height + 8, win.productMenu())
        },
        ToolbarButton {
            round: true
            symbol: "sidebar-right"
            checked: win.inspectorOpen
            Accessible.name: "Hide or show the Inspectors (⌥⌘0)"
            onClicked: win.inspectorOpen = !win.inspectorOpen
        }
    ]

    function productMenu() {
        return [
            { header: "Product" },
            { text: "Run", shortcut: "⌘R", symbol: "play", action: () => app.run() },
            { text: "Test", shortcut: "⌘U", action: () => app.test() },
            { text: "Build", shortcut: "⌘B", symbol: "hammer", action: () => app.build() },
            { text: "Clean Build Folder", shortcut: "⇧⌘K", action: () => app.clean() },
            { text: "Stop", shortcut: "⌘.", enabled: app.busy, action: () => app.stop() },
            { separator: true },
            { header: "File" },
            { text: "New File…", shortcut: "⌘N", action: () => win.promptNewItem(win.newItemFolder(), false) },
            { text: "New Project…", shortcut: "⇧⌘N", action: () => newProject.open() },
            { text: "Open…", shortcut: "⌘O", action: () => openPanel.open() },
            { text: "Open Quickly…", shortcut: "⇧⌘O", action: () => openQuickly.open() },
            { text: "Save All", shortcut: "⌥⌘S", action: () => editorArea.saveAll(null) },
            { separator: true },
            { header: "View" },
            { text: "Navigator", shortcut: "⌘0", checked: navigatorOpen, action: () => navigatorOpen = !navigatorOpen },
            { text: "Debug Area", shortcut: "⇧⌘Y", checked: debugOpen, action: () => debugOpen = !debugOpen },
            { text: "Inspectors", shortcut: "⌥⌘0", checked: inspectorOpen, action: () => inspectorOpen = !inspectorOpen },
            { text: "Minimap", checked: app.settings.showMinimap !== false, action: () => app.saveSettings({ showMinimap: app.settings.showMinimap === false }) },
            { separator: true },
            { text: "Simulator", symbol: "smartphone", action: () => { app.simulatorOpen = true } },
            { text: "Settings…", shortcut: "⌘,", symbol: "gear", action: () => settingsSheet.open() },
            { text: "Keyboard Shortcuts", action: () => shortcutsSheet.open() },
        ]
    }

    // ------------------------------------------------------------ navigator
    sidebar: [
        Navigator {
            id: navigator
            anchors.fill: parent
            app: win.app
            backend: win.backend
            selectedPath: editorArea.currentIsFile ? editorArea.currentPath : ""
            onOpenFile: (path, line, column) => editorArea.open(path, line, column)
            onOpenReport: (report) => editorArea.openLog(report.title + " — " + report.time, win.app.logs[report.gen] || "(no output)")
            onFileMenu: (from, x, y, path, isDir) => win.fileMenu(from, x, y, path, isDir)
        }
    ]

    function newItemFolder() {
        const p = editorArea.currentIsFile ? editorArea.currentPath : ""
        return p ? p.substring(0, p.lastIndexOf("/")) : app.project.root
    }

    function fileMenu(from, x, y, path, isDir) {
        const dir = isDir ? path : path.substring(0, path.lastIndexOf("/"))
        const isRoot = path === app.project.root
        menu.popup(from, x, y, [
            { text: "New File…", action: () => win.promptNewItem(dir, false) },
            { text: "New Folder…", action: () => win.promptNewItem(dir, true) },
            { separator: true },
            { text: "Rename…", enabled: !isRoot, action: () => win.promptRename(path) },
            { text: "Show in Files", action: () => Quickshell.execDetached(["gg-files", "--select", path]) },
            { text: "Copy Path", action: () => Quickshell.clipboardText = path },
            { separator: true },
            { text: "Move to Trash", destructive: true, enabled: !isRoot, action: () => win.confirmTrash(path) },
        ])
    }

    function promptNewItem(dir, folder) {
        prompt.ask(folder ? "New Folder" : "New File", folder ? "New Folder" : "File.swift", folder ? "Create" : "Create",
            (name) => backend.call("newFile", { dir: dir, name: name, folder: folder }, (r) => {
                if (!r.ok) { app.alertRequested("Couldn't Create “" + name + "”", r.error); return }
                app.refreshTree()
                navigator.reveal(r.path)
                if (!folder) editorArea.open(r.path, 0, 0)
            }))
    }

    function promptRename(path) {
        const name = path.split("/").pop()
        prompt.ask("Rename “" + name + "”", name, "Rename", (newName) => {
            if (newName === name) return
            backend.call("rename", { path: path, name: newName }, (r) => {
                if (!r.ok) { app.alertRequested("Couldn't Rename “" + name + "”", r.error); return }
                const wasOpen = editorArea.indexOf(path) >= 0
                editorArea.forget(path)
                app.refreshTree()
                if (wasOpen) editorArea.open(r.path, 0, 0)
            })
        })
    }

    function confirmTrash(path) {
        const name = path.split("/").pop()
        confirm.ask("Move “" + name + "” to the Trash?", "You can restore it from the Trash in Files.",
            [{ text: "Cancel", id: "cancel" }, { text: "Move to Trash", id: "trash", destructive: true }],
            (choice) => {
                if (choice !== "trash") return
                backend.call("trash", { path: path }, (r) => {
                    if (!r.ok) { app.alertRequested("Couldn't Move “" + name + "” to the Trash", r.error); return }
                    editorArea.forget(path)
                    app.refreshTree()
                })
            })
    }

    // --------------------------------------------------- editor and debug
    Item {
        anchors.fill: parent

        EditorArea {
            id: editorArea
            width: parent.width
            height: parent.height - (win.debugOpen ? debugArea.height : 0)
            app: win.app
            backend: win.backend
            menu: menu
            onError: (title, message) => win.app.alertRequested(title, message)
            onFileShown: (path) => { if (path && !path.startsWith("log:")) navigator.reveal(path) }
            onFindInProjectRequested: (text) => { win.navigatorOpen = true; navigator.focusFind(text) }
            onCloseConfirm: (index, proceed) => confirm.ask(
                "Do you want to keep the changes you made to “" + editorArea.documents.get(index).title + "”?",
                "Your changes will be lost if you don't save them.",
                [{ text: "Don't Save", id: "discard", destructive: true }, { text: "Cancel", id: "cancel" }, { text: "Save", id: "save", prominent: true }],
                proceed)
        }

        DebugArea {
            id: debugArea
            visible: win.debugOpen
            y: parent.height - height
            width: parent.width
            height: Math.max(90, Math.min(win.debugHeight, parent.height - 160))
            app: win.app
            backend: win.backend
            onHideRequested: win.debugOpen = false
            onResizeBy: (dy) => win.debugHeight = Math.max(90, win.debugHeight - dy)
        }
    }

    trailingSidebar: [
        Inspector {
            anchors.fill: parent
            app: win.app
            backend: win.backend
            menuParent: win.overlay
            path: editorArea.currentIsFile ? editorArea.currentPath : ""
            editor: editorArea.currentIsFile ? editorArea.currentEditor : null
        }
    ]

    // ---------------------------------------------------------------- menus
    PopupMenu { id: menu; parent: win.overlay; menuWidth: 250 }

    // Ask: a message with buttons. choice(id) gets the button's id.
    Sheet {
        id: confirm
        parent: win.overlay
        panelWidth: 440
        property string heading
        property string message
        property var buttons: []
        property var callback: null
        function ask(h, m, b, cb) { heading = h; message = m; buttons = b; callback = cb; open() }
        function choose(id) { const cb = callback; callback = null; close(); if (cb) cb(id) }
        onClosed: if (callback) { const cb = callback; callback = null; cb("cancel") }
        Column {
            width: parent.width
            spacing: 10
            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 56; height: 56
                sourceSize: Qt.size(112, 112)
                source: Quickshell.iconPath("org.goldengate.LCode", true)
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: confirm.heading
                color: Theme.label
                font { family: Theme.fontUi; pixelSize: 14; weight: Font.Bold }
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: confirm.message
                visible: !!confirm.message
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: 12 }
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                topPadding: 6
                Repeater {
                    model: confirm.buttons
                    delegate: Button {
                        required property var modelData
                        text: modelData.text
                        prominent: !!modelData.prominent
                        destructive: !!modelData.destructive
                        onClicked: confirm.choose(modelData.id)
                    }
                }
            }
        }
    }

    // Ask for a name (new file, rename).
    Sheet {
        id: prompt
        parent: win.overlay
        panelWidth: 380
        property string heading
        property string accept
        property var callback: null
        function ask(h, initial, a, cb) {
            heading = h; accept = a; callback = cb
            nameField.text = initial
            open()
            nameField.input.forceActiveFocus()
            const dot = initial.lastIndexOf(".")
            nameField.input.select(0, dot > 0 ? dot : initial.length)
        }
        function finish() {
            const name = nameField.text.trim()
            if (!name) return
            const cb = callback
            close()
            if (cb) cb(name)
        }
        Column {
            width: parent.width
            spacing: 12
            Text {
                text: prompt.heading
                color: Theme.label
                font { family: Theme.fontUi; pixelSize: 14; weight: Font.Bold }
            }
            TextField {
                id: nameField
                width: parent.width
                height: 30
                onAccepted: prompt.finish()
            }
            Row {
                anchors.right: parent.right
                spacing: 8
                Button { text: "Cancel"; onClicked: prompt.close() }
                Button { text: prompt.accept; prominent: true; onClicked: prompt.finish() }
            }
        }
    }

    OpenQuickly {
        id: openQuickly
        parent: win.overlay
        backend: win.backend
        app: win.app
        onChosen: (path) => editorArea.open(path, 0, 0)
    }

    NewProjectSheet {
        id: newProject
        parent: win.overlay
        app: win.app
        backend: win.backend
        onCreated: (root) => win.app.openProject(root)
    }

    OpenPanel {
        id: openPanel
        parent: win.overlay
        backend: win.backend
        onChosen: (path) => win.app.openProject(path)
    }

    SettingsSheet {
        id: settingsSheet
        parent: win.overlay
        app: win.app
    }

    ShortcutsSheet {
        id: shortcutsSheet
        parent: win.overlay
    }

    // ------------------------------------------------------------ shortcuts
    // Apple's ⌘ shortcuts: Golden Gate's keyd layer turns ⌘ into Ctrl in apps.
    Shortcut { sequence: "Ctrl+R"; onActivated: win.app.run() }
    Shortcut { sequence: "Ctrl+B"; onActivated: win.app.build() }
    Shortcut { sequence: "Ctrl+U"; onActivated: win.app.test() }
    Shortcut { sequence: "Ctrl+Shift+K"; onActivated: win.app.clean() }
    Shortcut { sequence: "Ctrl+."; onActivated: win.app.stop() }
    Shortcut { sequence: "Ctrl+S"; onActivated: if (editorArea.current >= 0) editorArea.save(editorArea.current, null) }
    Shortcut { sequence: "Ctrl+Alt+S"; onActivated: editorArea.saveAll(null) }
    Shortcut { sequence: "Ctrl+N"; onActivated: win.promptNewItem(win.newItemFolder(), false) }
    Shortcut { sequence: "Ctrl+Shift+N"; onActivated: newProject.open() }
    Shortcut { sequence: "Ctrl+O"; onActivated: openPanel.open() }
    Shortcut { sequence: "Ctrl+Shift+O"; onActivated: openQuickly.open() }
    Shortcut { sequence: "Ctrl+0"; onActivated: win.navigatorOpen = !win.navigatorOpen }
    Shortcut { sequence: "Ctrl+Shift+Y"; onActivated: win.debugOpen = !win.debugOpen }
    Shortcut { sequence: "Ctrl+Alt+0"; onActivated: win.inspectorOpen = !win.inspectorOpen }
    Shortcut { sequence: "Ctrl+1"; onActivated: { win.navigatorOpen = true; navigator.page = 0 } }
    Shortcut { sequence: "Ctrl+4"; onActivated: { win.navigatorOpen = true; navigator.page = 1 } }
    Shortcut { sequence: "Ctrl+5"; onActivated: { win.navigatorOpen = true; navigator.page = 2 } }
    Shortcut { sequence: "Ctrl+9"; onActivated: { win.navigatorOpen = true; navigator.page = 3 } }
    Shortcut { sequence: "Ctrl+Shift+F"; onActivated: { win.navigatorOpen = true; navigator.focusFind(editorArea.currentEditor ? editorArea.currentEditor.editor.selectedText : "") } }
    Shortcut { sequence: "Ctrl+F"; onActivated: editorArea.showFind(false) }
    Shortcut { sequence: "Ctrl+Alt+F"; onActivated: editorArea.showFind(true) }
    Shortcut { sequence: "Ctrl+G"; onActivated: editorArea.findNext(true) }
    Shortcut { sequence: "Ctrl+Shift+G"; onActivated: editorArea.findNext(false) }
    Shortcut { sequence: "Ctrl+/"; onActivated: if (editorArea.currentEditor) editorArea.currentEditor.toggleComment() }
    Shortcut { sequence: "Ctrl+L"; onActivated: if (editorArea.currentEditor) goToLine.ask() }
    Shortcut { sequence: "Ctrl+K"; onActivated: win.app.consoleText = "" }
    Shortcut { sequence: "Ctrl+,"; onActivated: settingsSheet.open() }
    Shortcut { sequence: "Ctrl+Shift+2"; onActivated: win.app.simulatorOpen = true }

    Sheet {
        id: goToLine
        parent: win.overlay
        panelWidth: 320
        function ask() { lineField.text = ""; open(); lineField.input.forceActiveFocus() }
        Column {
            width: parent.width
            spacing: 10
            Text { text: "Go to Line"; color: Theme.label; font { family: Theme.fontUi; pixelSize: 14; weight: Font.Bold } }
            TextField {
                id: lineField
                width: parent.width
                height: 30
                placeholder: "Line number, or line:column"
                onAccepted: {
                    const [l, c] = text.split(":").map((v) => parseInt(v, 10))
                    goToLine.close()
                    if (l > 0 && editorArea.currentEditor) editorArea.currentEditor.goTo(l, c > 0 ? c : 1)
                }
            }
        }
    }
}
