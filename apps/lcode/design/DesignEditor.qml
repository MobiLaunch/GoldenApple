// The App Designer: LCode's Interface Builder for CitronOS apps. The outline
// on the left, the canvas in the middle (light, dark or both; Select or Live),
// the inspectors in the window's trailing sidebar (DesignInspector), and the
// Library (⇧⌘L) to add things from.
//
// It edits Interface.lcdesign and plays well with the editor area: `text` is
// the document, `savedText` what's on disk, `revision` bumps on every change.
import QtQuick
import "../../lib"
import "../../lib/theme"
import "../../lib/kit" as Kit
import "../../lib/kit/catalog.js" as Catalog
import "../design.js" as Design

Item {
    id: designer
    property string path: ""
    property string text: ""
    property string savedText: ""
    property int revision: 0
    property bool readOnly: false
    property var menu: null                   // the window's PopupMenu
    property Item overlay: null               // the window's overlay layer
    property var backend: null
    property var app: null
    readonly property var editor: null        // no text editor here (EditorArea checks)
    readonly property int cursorLine: 0
    signal openAsText()
    signal showCode(string title, string code)
    signal error(string title, string message)

    property var doc: null
    property string loadError: ""
    property string screenId: ""
    property var selection: ({ kind: "app", id: "" })
    property string mode: "select"
    property string appearance: "light"
    property string device: "window"
    property bool outlineOpen: true
    property var clipboard: null
    readonly property string selectedNode: selection.kind === "node" ? selection.id : ""
    readonly property string assetBase: path ? "file://" + path.substring(0, path.lastIndexOf("/")) + "/Assets" : ""

    // ------------------------------------------------------------ loading
    function load(content) {
        try {
            doc = Design.parse(content)
            loadError = ""
        } catch (e) {
            doc = null
            loadError = String(e.message || e)
        }
        savedText = content
        text = content
        if (doc) {
            screenId = doc.screens[0].id
            runtime.screen = screenId
        }
    }
    function goTo(line, column) {
        // Build issues point at nodes: “… [screen#n7]”.
    }
    function revealNode(screen, id) {
        if (!doc) return
        if (screen && Design.screenById(doc, screen)) showScreen(screen)
        if (id && Design.find(doc, id)) selection = { kind: "node", id: id }
    }
    function toggleComment() {}

    // ------------------------------------------------------- undo and redo
    property var undoStack: []
    property var redoStack: []
    property string lastKey: ""
    property real lastTime: 0

    function commit(next, key) {
        if (!next || readOnly) return
        const now = Date.now()
        const coalesce = key && key === lastKey && now - lastTime < 1200
        if (!coalesce) {
            undoStack = undoStack.concat([text]).slice(-200)
            redoStack = []
        }
        lastKey = key || ""
        lastTime = now
        doc = next
        text = Design.serialize(next)
        revision++
        if (!Design.screenById(doc, screenId)) showScreen(doc.screens[0].id)
        if (selection.kind === "node" && !Design.find(doc, selection.id)) selection = { kind: "screen", id: screenId }
    }
    function restore(snapshot) {
        doc = Design.parse(snapshot)
        text = snapshot
        revision++
        if (!Design.screenById(doc, screenId)) showScreen(doc.screens[0].id)
        if (selection.kind === "node" && !Design.find(doc, selection.id)) selection = { kind: "screen", id: screenId }
    }
    function undo() {
        if (!undoStack.length) return
        redoStack = redoStack.concat([text])
        const s = undoStack[undoStack.length - 1]
        undoStack = undoStack.slice(0, -1)
        lastKey = ""
        restore(s)
    }
    function redo() {
        if (!redoStack.length) return
        undoStack = undoStack.concat([text])
        const s = redoStack[redoStack.length - 1]
        redoStack = redoStack.slice(0, -1)
        lastKey = ""
        restore(s)
    }

    // ------------------------------------------------------------ editing
    function showScreen(id) {
        screenId = id
        runtime.backStack = []
        runtime.screen = id
    }
    function setProps(id, patch, key) { commit(Design.update(doc, id, patch), key || (id + ":" + Object.keys(patch).join(","))) }
    function setActions(id, event, actions) { commit(Design.setActions(doc, id, event, actions), id + ":actions:" + event) }
    function setApp(patch, key) { commit(Design.updateApp(doc, patch), key || ("app:" + Object.keys(patch).join(","))) }
    function setScreen(id, patch, key) { commit(Design.updateScreen(doc, id, patch), key || ("screen:" + id + Object.keys(patch).join(","))) }

    function add(entry, parentId, index) {
        const node = Design.createNode(doc, entry)
        let at = parentId ? { parent: parentId, index: index } : Design.insertionPoint(doc, screenId, selectedNode)
        const hit = Design.find(doc, at.parent)
        if (hit && !Catalog.isContainer(hit.node.type)) at = hit.parent ? { parent: hit.parent.id, index: hit.index + 1 } : Design.insertionPoint(doc, screenId, "")
        try {
            commit(Design.insert(doc, at.parent, at.index, node))
            selection = { kind: "node", id: node.id }
        } catch (e) {
            error("Couldn't Add " + Catalog.title(node.type), String(e.message || e))
        }
    }
    function drop(payload, parentId, index) {
        if (payload.entry) { add(payload.entry, parentId, index); return }
        if (payload.move) {
            commit(Design.move(doc, payload.move, parentId, index))
            selection = { kind: "node", id: payload.move }
        }
    }
    function removeSelected() {
        if (selection.kind === "node") {
            const hit = Design.find(doc, selection.id)
            if (!hit || !hit.parent) return
            commit(Design.remove(doc, selection.id))
            selection = { kind: "node", id: hit.parent.id }
        } else if (selection.kind === "screen" && doc.screens.length > 1) {
            commit(Design.removeScreen(doc, selection.id))
            selection = { kind: "screen", id: screenId }
        } else if (selection.kind === "variable") {
            commit(Design.removeVariable(doc, selection.id))
            selection = { kind: "app", id: "" }
        } else if (selection.kind === "color") {
            commit(Design.removeColor(doc, selection.id))
            selection = { kind: "app", id: "" }
        }
    }
    function duplicateSelected() {
        if (!selectedNode) return
        const r = Design.duplicate(doc, selectedNode)
        commit(r.doc)
        selection = { kind: "node", id: r.id }
    }
    function embedSelected(entry) {
        if (!selectedNode) return
        const r = Design.embed(doc, selectedNode, entry)
        commit(r.doc)
        selection = { kind: "node", id: r.id }
    }
    function unembedSelected() {
        if (!selectedNode) return
        const hit = Design.find(doc, selectedNode)
        commit(Design.unembed(doc, selectedNode))
        selection = hit && hit.parent ? { kind: "node", id: hit.parent.id } : { kind: "screen", id: screenId }
    }
    function moveSelected(delta) {
        const hit = selectedNode ? Design.find(doc, selectedNode) : null
        if (!hit || !hit.parent) return
        const to = hit.index + delta
        if (to < 0 || to >= hit.parent.children.length) return
        commit(Design.move(doc, selectedNode, hit.parent.id, delta > 0 ? to + 1 : to))
    }
    function selectParent() {
        const hit = selectedNode ? Design.find(doc, selectedNode) : null
        if (hit && hit.parent) selection = { kind: "node", id: hit.parent.id }
        else selection = { kind: "screen", id: screenId }
    }
    function copySelected(cut) {
        const hit = selectedNode ? Design.find(doc, selectedNode) : null
        if (!hit) return
        clipboard = Design.clone(hit.node)
        if (cut && hit.parent) removeSelected()
    }
    function paste() {
        if (!clipboard) return
        const node = Design.reid(doc, clipboard)
        const at = Design.insertionPoint(doc, screenId, selectedNode)
        commit(Design.insert(doc, at.parent, at.index, node))
        selection = { kind: "node", id: node.id }
    }
    function addScreen() {
        const r = Design.addScreen(doc, "Screen " + (doc.screens.length + 1))
        commit(r.doc)
        showScreen(r.id)
        selection = { kind: "screen", id: r.id }
    }
    function addVariable(type) {
        const r = Design.addVariable(doc, type)
        commit(r.doc)
        selection = { kind: "variable", id: r.name }
        return r.name
    }
    function addColor() {
        const r = Design.addColor(doc)
        commit(r.doc)
        selection = { kind: "color", id: r.name }
    }

    function nodeMenu(id, from, x, y) {
        const hit = id ? Design.find(doc, id) : null
        const container = hit && Catalog.isContainer(hit.node.type)
        const items = [
            { text: "Add from Library…", shortcut: "⇧⌘L", action: () => openLibrary(from, x, y) },
            { separator: true },
            { text: "Embed In", enabled: !!hit, submenu: [
                { text: "Vertical Stack", symbol: "stack-vertical", action: () => embedSelected("VStack") },
                { text: "Horizontal Stack", symbol: "stack-horizontal", action: () => embedSelected("HStack") },
                { text: "Overlay Stack", symbol: "stack-depth", action: () => embedSelected("ZStack") },
                { text: "Scroll View", symbol: "scroll", action: () => embedSelected("ScrollView") },
                { text: "Card", symbol: "card", action: () => embedSelected(Catalog.CATALOG.library.find((e) => e.title === "Card")) },
            ] },
            { text: "Unembed", enabled: !!container && !!hit.parent, action: () => unembedSelected() },
            { separator: true },
            { text: "Cut", shortcut: "⌘X", enabled: !!hit && !!hit.parent, action: () => copySelected(true) },
            { text: "Copy", shortcut: "⌘C", enabled: !!hit, action: () => copySelected(false) },
            { text: "Paste", shortcut: "⌘V", enabled: !!clipboard, action: () => paste() },
            { text: "Duplicate", shortcut: "⌘D", enabled: !!hit && !!hit.parent, action: () => duplicateSelected() },
            { separator: true },
            { text: "Move Up", shortcut: "⌥⌘↑", enabled: !!hit && hit.index > 0, action: () => moveSelected(-1) },
            { text: "Move Down", shortcut: "⌥⌘↓", enabled: !!hit && !!hit.parent && hit.index < hit.parent.children.length - 1, action: () => moveSelected(1) },
            { text: "Select Parent", shortcut: "⎋", enabled: !!hit, action: () => selectParent() },
            { separator: true },
            { text: "Delete", shortcut: "⌫", destructive: true, enabled: !!hit && !!hit.parent, action: () => removeSelected() },
        ]
        menu.popup(from, x, y, items)
    }

    function openLibrary(from, x, y) {
        library.parent = overlay
        library.openAt(from || libraryButton, x === undefined ? 0 : x, y === undefined ? libraryButton.height + 6 : y)
    }

    // Edit a text right on the canvas (double-click).
    function editText(id) {
        const hit = Design.find(doc, id)
        if (!hit) return
        const key = ["text", "title", "label", "placeholder"].find((k) => typeof (hit.node.props || {})[k] === "string")
        if (!key) return
        inlineEdit.key = key
        inlineEdit.nodeId = id
        inlineField.text = hit.node.props[key]
        inlineEdit.parent = overlay
        inlineEdit.openAt(canvas, canvas.width / 2 - 140, 60)
        inlineField.input.forceActiveFocus()
        inlineField.input.selectAll()
    }

    function generatedCode() {
        if (!backend || !doc) return
        backend.call("designCode", { text: text, screen: screenId }, (r) => {
            if (r.ok) designer.showCode((Design.screenById(doc, screenId) || {}).title + ".qml (generated)", r.code)
            else designer.error("Couldn't Generate the Code", r.error)
        })
    }

    // ------------------------------------------------------------ runtime
    Kit.AppRuntime {
        id: runtime
        sandbox: true
        initial: designer.doc ? Design.initialValues(designer.doc) : ({})
        screens: designer.doc ? designer.doc.screens.map((s) => s.id) : []
        onScreenChanged: if (designer.doc && screen && screen !== designer.screenId && Design.screenById(designer.doc, screen)) designer.screenId = screen
        onNotice: (t) => { toast.text = t; toast.shown = true; toastTimer.restart() }
    }
    readonly property alias runtime: runtime

    // ------------------------------------------------------------- layout
    Rectangle {
        id: bar
        width: parent.width
        height: 36
        color: "transparent"
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.separator }
        Row {
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            ToolbarButton {
                symbol: "sidebar"
                symbolSize: 14
                checked: designer.outlineOpen
                Accessible.name: "Hide or show the Document Outline"
                onClicked: designer.outlineOpen = !designer.outlineOpen
            }
            ToolbarButton {
                id: screenButton
                symbol: designer.doc ? ((Design.screenById(designer.doc, designer.screenId) || {}).symbol || "doc") : "doc"
                symbolSize: 14
                text: designer.doc ? ((Design.screenById(designer.doc, designer.screenId) || {}).title || "") : ""
                onClicked: designer.menu.popup(screenButton, 0, screenButton.height + 4,
                    [{ header: "Screens" }].concat(designer.doc.screens.map((s) => ({ text: s.title || s.id, symbol: s.symbol || "doc",
                        checked: s.id === designer.screenId, action: () => { designer.showScreen(s.id); designer.selection = { kind: "screen", id: s.id } } })),
                        [{ separator: true }, { text: "New Screen", action: () => designer.addScreen() }]))
            }
        }
        Row {
            anchors.centerIn: parent
            spacing: 10
            Segmented {
                anchors.verticalCenter: parent.verticalCenter
                options: ["Select", "Live"]
                current: designer.mode === "live" ? 1 : 0
                onPicked: (i) => designer.mode = i === 1 ? "live" : "select"
            }
            ToolbarButton {
                visible: designer.mode === "live"
                anchors.verticalCenter: parent.verticalCenter
                symbol: "arrow-clockwise"
                symbolSize: 14
                Accessible.name: "Reset the app's variables"
                onClicked: { runtime.reset(); designer.showScreen(designer.screenId) }
            }
            ToolbarButton {
                id: deviceButton
                anchors.verticalCenter: parent.verticalCenter
                symbol: "window"
                symbolSize: 14
                text: canvas.size.w + " × " + canvas.size.h
                onClicked: designer.menu.popup(deviceButton, 0, deviceButton.height + 4, [
                    { header: "Preview Size" },
                    { text: "Window (" + (designer.doc.app.width || 900) + " × " + (designer.doc.app.height || 620) + ")", checked: designer.device === "window", action: () => designer.device = "window" },
                    { text: "Compact", checked: designer.device === "compact", action: () => designer.device = "compact" },
                    { text: "Large (1280 × 800)", checked: designer.device === "large", action: () => designer.device = "large" },
                ])
            }
            Segmented {
                anchors.verticalCenter: parent.verticalCenter
                options: ["Light", "Dark", "Both"]
                current: ["light", "dark", "both"].indexOf(designer.appearance)
                onPicked: (i) => designer.appearance = ["light", "dark", "both"][i]
            }
            ToolbarPill {
                anchors.verticalCenter: parent.verticalCenter
                ToolbarButton { symbol: "minus"; symbolSize: 12; onClicked: canvas.zoom = Math.max(0.25, canvas.zoom / 1.2) }
                ToolbarButton { text: Math.round(canvas.zoom * 100) + "%"; onClicked: canvas.fit() }
                ToolbarButton { symbol: "plus"; symbolSize: 12; onClicked: canvas.zoom = Math.min(3, canvas.zoom * 1.2) }
            }
        }
        Row {
            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            spacing: 6
            ToolbarButton {
                id: libraryButton
                symbol: "plus"
                symbolSize: 13
                text: "Library"
                Accessible.name: "Library (⇧⌘L)"
                onClicked: designer.openLibrary()
            }
            ToolbarButton {
                id: moreButton
                symbol: "ellipsis"
                symbolSize: 14
                onClicked: designer.menu.popup(moreButton, moreButton.width - 230, moreButton.height + 4, [
                    { text: "Show Generated QML", symbol: "code", action: () => designer.generatedCode() },
                    { text: "Open as Source Code", action: () => designer.openAsText() },
                    { separator: true },
                    { text: "Undo", shortcut: "⌘Z", enabled: designer.undoStack.length > 0, action: () => designer.undo() },
                    { text: "Redo", shortcut: "⇧⌘Z", enabled: designer.redoStack.length > 0, action: () => designer.redo() },
                ])
            }
        }
    }

    Outline {
        id: outline
        visible: designer.outlineOpen && !!designer.doc
        y: bar.height
        width: designer.outlineOpen ? 250 : 0
        height: parent.height - y
        doc: designer.doc
        screenId: designer.screenId
        selection: designer.selection
        ghost: ghost
        onSelect: (s) => {
            designer.selection = s
            if (s.kind === "screen") designer.showScreen(s.id)
        }
        onContextMenu: (id, from, x, y) => designer.nodeMenu(id, from, x, y)
        onAddScreen: (from) => designer.addScreen()
        onAddVariable: (from) => designer.menu.popup(from, 0, from.height + 4, [
            { header: "New Variable" },
            { text: "Text", action: () => designer.addVariable("text") },
            { text: "Number", action: () => designer.addVariable("number") },
            { text: "On/Off", action: () => designer.addVariable("bool") },
            { text: "List", action: () => designer.addVariable("list") },
        ])
        onAddColor: designer.addColor()
        onDropRequested: (payload, parentId, index) => designer.drop(payload, parentId, index)
    }
    Rectangle {
        visible: outline.visible
        x: outline.width
        y: bar.height
        width: 1
        height: parent.height - y
        color: Theme.separator
    }

    DesignCanvas {
        id: canvas
        visible: !!designer.doc
        x: outline.visible ? outline.width + 1 : 0
        y: bar.height
        width: parent.width - x
        height: parent.height - y
        doc: designer.doc
        screenId: designer.screenId
        selectedId: designer.selectedNode
        mode: designer.mode
        appearance: designer.appearance
        device: designer.device
        runtime: runtime
        assetBase: designer.assetBase
        onSelectRequested: (id) => designer.selection = id ? { kind: "node", id: id } : { kind: "screen", id: designer.screenId }
        onScreenRequested: (id) => { designer.showScreen(id); designer.selection = { kind: "screen", id: id } }
        onContextMenuRequested: (id, x, y) => designer.nodeMenu(id, canvas, x - canvas.x + canvas.x, y)
        onDropRequested: (payload, parentId, index) => designer.drop(payload, parentId, index)
        onEditTextRequested: (id) => designer.editText(id)
        Component.onCompleted: Qt.callLater(fit)
        onWidthChanged: if (zoom === 1 || zoom < 1) fitTimer.restart()
        Timer { id: fitTimer; interval: 50; onTriggered: canvas.fit() }
    }

    // What the sandbox did instead of running a command, opening a page, …
    Rectangle {
        id: toast
        property bool shown: false
        property alias text: toastText.text
        visible: opacity > 0
        opacity: shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
        anchors { horizontalCenter: canvas.horizontalCenter; bottom: parent.bottom; bottomMargin: 16 }
        width: toastText.implicitWidth + 28
        height: 30
        radius: 15
        color: Theme.dark ? "#ee3a3a3c" : "#ee2c2c2e"
        Text {
            id: toastText
            anchors.centerIn: parent
            color: "white"
            font { family: Theme.fontUi; pixelSize: 12 }
        }
        Timer { id: toastTimer; interval: 2600; onTriggered: toast.shown = false }
    }

    // A design that can't be read.
    EmptyState {
        anchors.fill: parent
        visible: !designer.doc
        symbol: "warning"
        title: "Can't Open the Design"
        text: designer.loadError + "\nOpen it as source code to fix it."
    }
    Button {
        visible: !designer.doc
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 40 }
        text: "Open as Source Code"
        onClicked: designer.openAsText()
    }

    // ----------------------------------------------------- popovers, drag
    DragGhost { id: ghost; parent: designer.overlay }
    Library {
        id: library
        ghost: ghost
        onChosen: (entry) => designer.add(entry)
    }
    Popover {
        id: inlineEdit
        property string key: ""
        property string nodeId: ""
        panelWidth: 280
        TextField {
            id: inlineField
            width: parent.width
            height: 30
            onAccepted: { designer.setProps(inlineEdit.nodeId, { [inlineEdit.key]: text }); inlineEdit.close() }
        }
    }

    // ---------------------------------------------------------- shortcuts
    readonly property bool active: visible && !!doc
    readonly property bool typing: {
        const f = Window.activeFocusItem
        return !!f && f.cursorPosition !== undefined
    }
    Shortcut { sequence: "Ctrl+Z"; enabled: designer.active && !designer.typing; onActivated: designer.undo() }
    Shortcut { sequences: ["Ctrl+Shift+Z", "Ctrl+Y"]; enabled: designer.active && !designer.typing; onActivated: designer.redo() }
    Shortcut { sequences: ["Delete", "Backspace"]; enabled: designer.active && !designer.typing; onActivated: designer.removeSelected() }
    Shortcut { sequence: "Ctrl+D"; enabled: designer.active && !designer.typing; onActivated: designer.duplicateSelected() }
    Shortcut { sequence: "Ctrl+C"; enabled: designer.active && !designer.typing; onActivated: designer.copySelected(false) }
    Shortcut { sequence: "Ctrl+X"; enabled: designer.active && !designer.typing; onActivated: designer.copySelected(true) }
    Shortcut { sequence: "Ctrl+V"; enabled: designer.active && !designer.typing; onActivated: designer.paste() }
    Shortcut { sequence: "Ctrl+Shift+L"; enabled: designer.active; onActivated: designer.openLibrary() }
    Shortcut { sequence: "Escape"; enabled: designer.active && !designer.typing && !library.visible; onActivated: designer.selectParent() }
    Shortcut { sequence: "Ctrl+Alt+Up"; enabled: designer.active && !designer.typing; onActivated: designer.moveSelected(-1) }
    Shortcut { sequence: "Ctrl+Alt+Down"; enabled: designer.active && !designer.typing; onActivated: designer.moveSelected(1) }
    Shortcut { sequence: "Ctrl+Alt+Return"; enabled: designer.active; onActivated: designer.mode = designer.mode === "live" ? "select" : "live" }
}
