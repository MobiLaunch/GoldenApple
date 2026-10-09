// The project window, laid out like Xcode on macOS 27.
//   toolbar:  sidebar ▸ Run/Stop ▸ scheme › destination ▸ activity view ▸ + ⋯ inspector
//   sidebar:  navigators (Project, Find, Issues, Reports)
//   content:  tabs, jump bar, editor, debug area
//   trailing: inspectors
import Quickshell
import QtQuick
import "../lib"
import "../lib/theme"
import "languages.js" as Languages
import "design"
import "devices.js" as Devices
import "commands.js" as Commands

AppWindow {
    id: win
    objectName: "workspace"
    property var app
    property var backend
    property bool navigatorOpen: true
    property bool inspectorOpen: true
    property bool debugOpen: true
    property bool designDebugOpen: false      // the console stays out of the way of the App Designer
    // The console keeps out of the way of the App Designer and the project editor.
    readonly property bool designing: !!editorArea.currentDesigner || editorArea.currentPath === "project:"
    readonly property bool showDebug: designing ? designDebugOpen : debugOpen
    function toggleDebug() { if (designing) designDebugOpen = !designDebugOpen; else debugOpen = !debugOpen }
    property real debugHeight: 210
    // The debug pane docks to the editor rather than appearing as a second
    // floating surface. One animated boundary controls editor height and the
    // pane's top edge; resizing with the pointer remains immediate.
    property bool debugResizing: false
    property bool debugMotionReady: false
    property real presentedDebugHeight: showDebug
        ? Math.max(90, Math.min(debugHeight, Math.max(90, height - toolbarHeight - 160)))
        : 0
    Behavior on presentedDebugHeight {
        enabled: win.debugMotionReady && !Theme.reduceMotion && !win.debugResizing
        NumberAnimation { duration: 205; easing.type: Easing.OutCubic }
    }
    Timer {
        id: debugResizeIdle
        interval: 160
        onTriggered: win.debugResizing = false
    }
    function resizeDebug(dy) {
        debugResizing = true
        debugHeight = Math.max(90, debugHeight - dy)
        debugResizeIdle.restart()
    }

    title: app.project ? app.project.name : "LCode"
    implicitWidth: Math.min(1480, (Quickshell.screens[0]?.width ?? 1600) - 60)
    implicitHeight: Math.min(920, (Quickshell.screens[0]?.height ?? 1000) - 100)
    minimumSize: Qt.size(940, 560)
    sidebarWidth: navigatorOpen ? 270 : 0
    trailingSidebarWidth: inspectorOpen ? 260 : 0
    background: Theme.contentBg
    closeAction: () => win.requestClose()
    Component.onDestruction: if (win.app && win.app.quitHandler === win.requestClose) win.app.quitHandler = null
    appearance: app.appearance

    // ------------------------------------------------------------ lifecycle
    Component.onCompleted: {
        app.quitHandler = win.requestClose
        app.beforeTask = (then) => editorArea.saveAll((ok) => { if (ok) then() })
        // Settings ▸ General: reopen the files you had open, or start fresh.
        const st = app.settings.reopenFiles === false ? {} : (app.project.state || {})
        for (const p of (st.open_files || [])) editorArea.open(p, 0, 0)
        // gg-lcode path/to/File.swift (like xed) opens the package at that file.
        const launched = Quickshell.env("LCODE_FILE") || ""
        if (launched) editorArea.open(launched, 0, 0)
        else if (st.selected_file) editorArea.open(st.selected_file, 0, 0)
        else if (!(st.open_files || []).length) openDefaultFile.start()
        win.debugMotionReady = true
    }
    Timer {
        id: openDefaultFile
        interval: 300
        onTriggered: {
            const files = win.app.nodes.filter((n) => !n.dir)
            const wanted = Languages.START_FILES[win.app.project.toolchain] || []
            let pick = null
            for (const name of wanted) { pick = pick || files.find((n) => n.name === name) }
            pick = pick || files.find((n) => Languages.fileInfo(n.name).symbol === "code")
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
        function onRevealLocation(path, line, column, message) {
            win.navigatorOpen = true
            navigator.page = 2
            if (!path) return
            editorArea.open(path, line, column)
            // Design issues end with [screen#node]: select that node in the App Designer.
            const m = /\[([\w-]+)#(n\d+)\]$/.exec(message || "")
            if (m && path.endsWith(".lcdesign")) Qt.callLater(() => { if (editorArea.currentDesigner) editorArea.currentDesigner.revealNode(m[1], m[2]) })
        }
        function onAlertRequested(title, message) { confirm.ask(title, message, [{ text: "OK", id: "ok", prominent: true }], null) }
        function onOrganizerRequested() { organizer.open() }
        function onBehaviorRequested(event, b) {
            if (b.debug === "show") win.debugOpen = true
            else if (b.debug === "hide") win.debugOpen = false
            const page = { project: 0, issues: 2, reports: 3 }[b.navigator]
            if (page !== undefined) { win.navigatorOpen = true; navigator.page = page }
        }
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
                symbol: !win.app.project ? "terminal" : win.app.project.kind === "app" ? (win.app.project.toolchain === "goldengate" ? "window" : "smartphone")
                    : win.app.project.kind === "library" ? "layers" : "terminal"
                symbolSize: 15
                text: win.app.schemeName
                onClicked: menu.popup(schemeButton, 0, schemeButton.height + 8,
                    [{ header: "Schemes" }].concat(
                        win.app.project.products.length
                            ? win.app.project.products.map((p) => ({ text: p, checked: p === win.app.scheme, action: () => win.app.scheme = p }))
                            : [{ text: "No Executable Products", enabled: false }],
                        Languages.toolchain(win.app.project.toolchain).manifest
                            ? [{ separator: true }, { text: "Edit " + Languages.toolchain(win.app.project.toolchain).manifest + "…",
                                 action: () => editorArea.open(win.app.project.root + "/" + Languages.toolchain(win.app.project.toolchain).manifest, 0, 0) }]
                            : []))
            }
            Symbol {
                anchors.verticalCenter: parent.verticalCenter
                name: "chevron-small-right"
                size: 12
                tone: "gray"
            }
            ToolbarButton {
                id: destinationButton
                symbol: win.app.destination === "host" ? "window" : (win.app.deviceById(win.app.destination)?.tablet ? "tablet" : "smartphone")
                symbolSize: 15
                text: win.app.destinationName
                onClicked: menu.popup(destinationButton, 0, destinationButton.height + 8,
                    [{ header: "My Computer" },
                     { text: "My Linux PC", symbol: "window", checked: win.app.destination === "host", action: () => win.app.destination = "host" },
                     { header: "Simulators" }].concat(
                        win.app.devices.map((d) => ({ text: d.name, symbol: d.tablet ? "tablet" : "smartphone", checked: win.app.destination === d.id,
                                                      action: () => win.app.destination = d.id }))))
            }
        },
        ActivityView {
            id: activity
            app: win.app
            readonly property real leftEdge: schemePill.x + schemePill.width + 14
            // Follow the animated inspector boundary. Never overlap the
            // trailing toolbar actions when both sidebars are visible.
            readonly property real rightEdge: Math.min(win.width - 150, win.contentX + win.contentWidth - 12)
            readonly property real room: Math.max(0, rightEdge - leftEdge)
            width: Math.min(560, room)
            x: Math.max(leftEdge, (leftEdge + rightEdge - width) / 2)
            opacity: room >= 260 ? 1 : 0
            visible: opacity > 0.001
            enabled: room >= 260
            Behavior on opacity {
                NumberAnimation { duration: Theme.reduceMotion ? 0 : 125; easing.type: Easing.OutCubic }
            }
            anchors.verticalCenter: parent.verticalCenter
            onIssuesClicked: { win.navigatorOpen = true; navigator.page = 2 }
        }
    ]

    toolbarRight: [
        ToolbarButton {
            id: addButton
            round: true
            symbol: "plus"
            Accessible.name: editorArea.currentDesigner || editorArea.currentIsCode ? "Library (⇧⌘L)" : "New File (⌘N)"
            onClicked: editorArea.currentDesigner || editorArea.currentIsCode ? win.perform("library")
                                                                                 : win.promptNewItem(win.newItemFolder(), false)
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
            { text: "Run", shortcut: app.shortcutFor("run"), symbol: "play", action: () => app.run() },
            { text: "Test", shortcut: app.shortcutFor("test"), action: () => app.test() },
            { text: "Build", shortcut: app.shortcutFor("build"), symbol: "hammer", action: () => app.build() },
            { text: "Clean Build Folder", shortcut: app.shortcutFor("clean"), action: () => app.clean() },
            { text: "Archive", shortcut: app.shortcutFor("archive"), symbol: "shippingbox", enabled: !!app.project && app.project.kind !== "library", action: () => app.archive() },
            { text: "Organizer…", action: () => organizer.open() },
            { text: "Edit Scheme…", shortcut: app.shortcutFor("editScheme"), action: () => editorArea.openProjectEditor(3) },
            { text: "Project Settings…", action: () => editorArea.openProjectEditor(0) },
            { text: "Stop", shortcut: app.shortcutFor("stop"), enabled: app.busy, action: () => app.stop() },
            { separator: true },
            { header: "File" },
            { text: "New File…", shortcut: app.shortcutFor("newFile"), action: () => win.promptNewItem(win.newItemFolder(), false) },
            { text: "New Project…", shortcut: app.shortcutFor("newProject"), action: () => newProject.open() },
            { text: "Open…", shortcut: app.shortcutFor("open"), action: () => openPanel.open() },
            { text: "Open Quickly…", shortcut: app.shortcutFor("openQuickly"), action: () => openQuickly.open() },
            { text: "Save All", shortcut: app.shortcutFor("saveAll"), action: () => editorArea.saveAll(null) },
            { separator: true },
            { header: "View" },
            { text: "Navigator", shortcut: app.shortcutFor("toggleNavigator"), checked: navigatorOpen, action: () => navigatorOpen = !navigatorOpen },
            { text: "Debug Area", shortcut: app.shortcutFor("toggleDebug"), checked: showDebug, action: () => toggleDebug() },
            { text: "Inspectors", shortcut: app.shortcutFor("toggleInspector"), checked: inspectorOpen, action: () => inspectorOpen = !inspectorOpen },
            { text: "Minimap", checked: app.settings.showMinimap !== false, action: () => app.saveSettings({ showMinimap: app.settings.showMinimap === false }) },
            { separator: true },
            { text: "Simulator", symbol: "smartphone", action: () => { app.simulatorOpen = true } },
            { text: "Settings…", shortcut: app.shortcutFor("settings"), symbol: "gear", action: () => app.openSettings() },
            { text: "Keyboard Shortcuts", action: () => shortcutsSheet.open() },
            { text: "Customize Key Bindings…", action: () => app.openSettings(6) },
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
            onOpenProjectEditor: editorArea.openProjectEditor(0)
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
        prompt.ask(folder ? "New Folder" : "New File", folder ? "New Folder" : (Languages.NEW_FILE[app.project.toolchain] || "File.txt"), "Create",
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
        id: editorDock
        anchors.fill: parent
        clip: true

        EditorArea {
            id: editorArea
            objectName: "editorArea"
            width: parent.width
            height: Math.max(0, parent.height - win.presentedDebugHeight)
            app: win.app
            backend: win.backend
            menu: menu
            overlay: win.overlay
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
            visible: win.presentedDebugHeight > 0.5
            y: parent.height - win.presentedDebugHeight
            width: parent.width
            height: Math.max(90, Math.min(win.debugHeight, parent.height - 160))
            opacity: Math.max(0, Math.min(1, win.presentedDebugHeight / 70))
            app: win.app
            backend: win.backend
            onHideRequested: win.toggleDebug()
            resizeCoordinateSpace: editorDock
            onResizeBy: (dy) => win.resizeDebug(dy)
        }
    }

    trailingSidebar: [
        Inspector {
            anchors.fill: parent
            visible: !editorArea.currentDesigner
            app: win.app
            backend: win.backend
            menuParent: win.overlay
            path: editorArea.currentIsFile ? editorArea.currentPath : ""
            editor: editorArea.currentIsCode ? editorArea.currentEditor : null
        },
        // The App Designer's inspectors for the design in front.
        DesignInspector {
            anchors.fill: parent
            visible: !!editorArea.currentDesigner
            designer: editorArea.currentDesigner
            overlay: win.overlay
            backend: win.backend
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
                font { family: Theme.fontUi; pixelSize: Theme.fs(14); weight: Font.Bold }
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: confirm.message
                visible: !!confirm.message
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
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
                font { family: Theme.fontUi; pixelSize: Theme.fs(14); weight: Font.Bold }
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

    ShortcutsSheet {
        id: shortcutsSheet
        parent: win.overlay
        app: win.app
    }

    CodeLibrary {
        id: codeLibrary
        objectName: "codeLibrary"
        parent: win.overlay
        app: win.app
        backend: win.backend
        editorArea: editorArea
    }

    OrganizerSheet {
        id: organizer
        objectName: "organizer"
        parent: win.overlay
        app: win.app
        backend: win.backend
    }

    // ------------------------------------------------------------ shortcuts
    // Apple's ⌘ shortcuts (CitronOS's keyd layer turns ⌘ into Ctrl in
    // apps), rebindable in Settings ▸ Key Bindings.
    function perform(id) {
        const ed = editorArea.currentEditor
        switch (id) {
        case "run": app.run(); break
        case "build": app.build(); break
        case "test": app.test(); break
        case "clean": app.clean(); break
        case "stop": app.stop(); break
        case "archive": if (app.project.kind !== "library") app.archive(); break
        case "editScheme": editorArea.openProjectEditor(3); break
        case "save": if (editorArea.current >= 0) editorArea.save(editorArea.current, null); break
        case "saveAll": editorArea.saveAll(null); break
        case "newFile": promptNewItem(newItemFolder(), false); break
        case "newProject": newProject.open(); break
        case "open": openPanel.open(); break
        case "openQuickly": openQuickly.open(); break
        case "find": editorArea.showFind(false); break
        case "findReplace": editorArea.showFind(true); break
        case "findNext": editorArea.findNext(true); break
        case "findPrevious": editorArea.findNext(false); break
        case "findInProject": navigatorOpen = true; navigator.focusFind(ed ? ed.editor.selectedText : ""); break
        case "toggleComment": if (ed) ed.toggleComment(); break
        case "complete": if (ed && editorArea.currentIsCode) editorArea.complete(); break
        case "goToLine": if (ed) goToLine.ask(); break
        case "fontBigger": app.saveSettings({ fontSize: Math.min(36, (app.settings.fontSize || 13) + 1) }); break
        case "fontSmaller": app.saveSettings({ fontSize: Math.max(8, (app.settings.fontSize || 13) - 1) }); break
        case "fontReset": app.saveSettings({ fontSize: 13 }); break
        case "library":
            if (editorArea.currentDesigner) editorArea.currentDesigner.openLibrary(addButton, addButton.width - 380, addButton.height + 8)
            else if (editorArea.currentIsCode) codeLibrary.openAt(addButton, addButton.width - 360, addButton.height + 8)
            break
        case "toggleNavigator": navigatorOpen = !navigatorOpen; break
        case "toggleDebug": toggleDebug(); break
        case "toggleInspector": inspectorOpen = !inspectorOpen; break
        case "projectNavigator": navigatorOpen = true; navigator.page = 0; break
        case "findNavigator": navigatorOpen = true; navigator.page = 1; break
        case "issueNavigator": navigatorOpen = true; navigator.page = 2; break
        case "reportNavigator": navigatorOpen = true; navigator.page = 3; break
        case "clearConsole": app.consoleText = ""; break
        case "simulator": app.simulatorOpen = true; break
        case "settings": app.openSettings(); break
        }
    }
    Instantiator {
        model: Commands.COMMANDS
        delegate: Shortcut {
            required property var modelData
            sequences: win.app.keysFor(modelData.id)
            enabled: sequences.length > 0
            onActivated: win.perform(modelData.id)
        }
    }

    Sheet {
        id: goToLine
        parent: win.overlay
        panelWidth: 320
        function ask() { lineField.text = ""; open(); lineField.input.forceActiveFocus() }
        Column {
            width: parent.width
            spacing: 10
            Text { text: "Go to Line"; color: Theme.label; font { family: Theme.fontUi; pixelSize: Theme.fs(14); weight: Font.Bold } }
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
