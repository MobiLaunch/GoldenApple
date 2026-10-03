// The editor area: tabs, the jump bar, find & replace and the editors, one
// CodeEditor per open tab so each keeps its undo history, cursor and scroll.
import Quickshell
import QtQuick
import "../lib"
import "../lib/theme"
import "../lib/syntax.js" as Syntax
import "languages.js" as Languages
import "design"

Item {
    id: area
    property var app
    property var backend
    property var menu                         // the window's PopupMenu
    property Item overlay: null               // the window's overlay (the designer's popovers)
    property int current: -1
    property bool findVisible: false
    property bool replaceVisible: false
    property var pendingJump: null            // { path, line, column } once the file has loaded
    signal fileShown(string path)
    signal error(string title, string message)
    signal closeConfirm(int index, var proceed)
    signal findInProjectRequested(string text)

    readonly property var currentEditor: current >= 0 && editors.count > current ? editorAt(current) : null
    readonly property string currentPath: current >= 0 && current < docs.count ? docs.get(current).path : ""
    // Files on disk: source code, or a design open in the App Designer.
    readonly property bool currentIsFile: current >= 0 && current < docs.count && (docs.get(current).kind === "file" || docs.get(current).kind === "design")
    readonly property bool currentIsCode: currentIsFile && docs.get(current).kind === "file"
    readonly property var currentDesigner: current >= 0 && current < docs.count && docs.get(current).kind === "design" ? currentEditor : null
    signal revealNodeRequested(string screen, string node)

    function editorAt(i) { const holder = editors.itemAt(i); return holder ? holder.item : null }
    function isFileKind(kind) { return kind === "file" || kind === "design" }
    onCurrentChanged: fileShown(currentPath)

    ListModel { id: docs }
    readonly property alias documents: docs

    function indexOf(path) {
        for (let i = 0; i < docs.count; i++) if (docs.get(i).path === path) return i
        return -1
    }

    // Open a file in a tab: a design in the App Designer (unless asText), anything else as text.
    function open(path, line, column, asText) {
        const i = indexOf(path)
        if (i >= 0) {
            if (asText && docs.get(i).kind === "design") { closeAt(i, false); Qt.callLater(() => area.open(path, line, column, true)); return }
            current = i
            const ed = editorAt(i)
            if (line > 0 && ed) ed.goTo(line, column)
            return
        }
        backend.call("read", { path: path }, (r) => {
            if (!r.ok) { area.error("Couldn't Open the File", r.error); return }
            if (area.indexOf(path) >= 0) return
            area.pendingJump = line > 0 ? { path: path, line: line, column: column } : null
            const kind = path.endsWith(".lcdesign") && !asText ? "design" : "file"
            docs.append({ path: path, title: path.split("/").pop(), kind: kind, locked: !!r.readOnly, dirty: false, content: r.text, lang: "" })
            area.current = docs.count - 1
        })
    }

    // A read-only tab: a build log, or generated code (with its language).
    function openLog(title, text, lang) {
        for (let i = 0; i < docs.count; i++) {
            if (docs.get(i).kind === "log" && docs.get(i).title === title) {
                editorAt(i).text = text
                current = i
                return
            }
        }
        docs.append({ path: "log:" + title, title: title, kind: "log", locked: true, dirty: false, content: text, lang: lang || "" })
        current = docs.count - 1
    }

    function closeAt(index, force) {
        if (index < 0 || index >= docs.count) return
        if (!force && docs.get(index).dirty) {
            area.closeConfirm(index, (choice) => {
                if (choice === "save") area.save(index, (ok) => { if (ok) area.closeAt(index, true) })
                else if (choice === "discard") area.closeAt(index, true)
            })
            return
        }
        docs.remove(index)
        if (current >= docs.count) current = docs.count - 1
        else if (index < current) current--
        else fileShown(currentPath)
    }

    // Close tabs for a path (or a folder's files) after it was deleted or renamed.
    function forget(path) {
        for (let i = docs.count - 1; i >= 0; i--) {
            const p = docs.get(i).path
            if (p === path || p.startsWith(path + "/")) closeAt(i, true)
        }
    }

    function save(index, done) {
        const doc = docs.get(index)
        const editor = editorAt(index)
        if (!doc || !isFileKind(doc.kind) || doc.locked || !editor) { if (done) done(true); return }
        const text = editor.text
        backend.call("write", { path: doc.path, text: text }, (r) => {
            if (r.ok) {
                editor.savedText = text
                if (/(Package\.swift|Cargo\.toml|meson\.build|pyproject\.toml)$/.test(doc.path)) area.app.refreshProject()
            } else {
                area.error("Couldn't Save “" + doc.title + "”", r.error)
            }
            if (done) done(r.ok)
        })
    }

    function saveAll(done) {
        const dirty = []
        for (let i = 0; i < docs.count; i++) if (docs.get(i).dirty) dirty.push(i)
        let left = dirty.length, allOk = true
        if (!left) { if (done) done(true); return }
        for (const i of dirty) save(i, (ok) => { allOk = allOk && ok; if (--left === 0 && done) done(allOk) })
    }

    function hasUnsaved() {
        for (let i = 0; i < docs.count; i++) if (docs.get(i).dirty) return true
        return false
    }

    function openFiles() {
        const out = []
        for (let i = 0; i < docs.count; i++) if (isFileKind(docs.get(i).kind)) out.push(docs.get(i).path)
        return out
    }

    function showFind(replace) {
        if (!currentEditor || !currentEditor.editor) return
        findVisible = true
        replaceVisible = !!replace
        const sel = currentEditor.editor.selectedText
        if (sel && !sel.includes("\n")) findField.text = sel
        findField.input.forceActiveFocus()
        findField.input.selectAll()
    }
    function hideFind() {
        findVisible = false
        if (currentEditor) currentEditor.editor.forceActiveFocus()
    }
    function findNext(forward) {
        if (currentEditor && findField.text) currentEditor.findNext(findField.text, forward, matchCase.checked)
    }

    // ---------------------------------------------------------------- tabs
    Rectangle {
        id: tabBar
        width: parent.width
        height: 34
        color: "transparent"
        ListView {
            id: tabs
            anchors { fill: parent; leftMargin: 8; rightMargin: 8; topMargin: 2; bottomMargin: 2 }
            orientation: ListView.Horizontal
            spacing: 4
            clip: true
            model: docs
            boundsBehavior: Flickable.StopAtBounds
            delegate: Item {
                id: tab
                required property int index
                required property string title
                required property string path
                required property bool dirty
                required property string kind
                readonly property bool selected: index === area.current
                width: Math.min(220, Math.max(120, tabLabel.implicitWidth + 64))
                height: tabs.height
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: tab.selected ? (Theme.dark ? "#26ffffff" : "#ffffff") : tabHover.hovered ? Theme.fill : "transparent"
                    border { width: tab.selected ? 1 : 0; color: Theme.dark ? "#1affffff" : "#14000000" }
                }
                Symbol {
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    size: 14
                    name: tab.kind === "log" ? "hammer" : Languages.fileInfo(tab.title).symbol
                    tone: "auto"
                    color: tab.kind === "log" ? "transparent" : Languages.fileInfo(tab.title).color
                }
                Text {
                    id: tabLabel
                    x: 32
                    width: parent.width - 64
                    anchors.verticalCenter: parent.verticalCenter
                    text: tab.title
                    elide: Text.ElideMiddle
                    color: tab.selected ? Theme.label : Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: 12; weight: tab.selected ? Font.DemiBold : Font.Normal; italic: tab.kind === "log" }
                }
                // Edited dot, which turns into the close button on hover.
                Item {
                    anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    width: 18; height: 18
                    Rectangle {
                        anchors.centerIn: parent
                        visible: tab.dirty && !closeHover.hovered && !tabHover.hovered
                        width: 7; height: 7; radius: 3.5
                        color: Theme.secondaryLabel
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: 9
                        visible: tabHover.hovered || tab.selected && !tab.dirty
                        color: closeHover.hovered ? Theme.fill : "transparent"
                        Symbol { anchors.centerIn: parent; name: "xmark"; size: 10; tone: "gray" }
                        HoverHandler { id: closeHover }
                        TapHandler { onTapped: area.closeAt(tab.index, false) }
                    }
                }
                HoverHandler { id: tabHover }
                TapHandler { onTapped: area.current = tab.index }
                TapHandler { acceptedButtons: Qt.MiddleButton; onTapped: area.closeAt(tab.index, false) }
            }
        }
    }

    // ------------------------------------------------------------ jump bar
    Item {
        id: jumpBar
        y: tabBar.height
        width: parent.width
        height: 28
        visible: area.current >= 0
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.separator }

        readonly property var crumbs: {
            const out = []
            const p = area.app.project
            if (!p || !area.currentPath) return out
            out.push({ title: p.name, dir: p.root, project: true })
            if (!area.currentIsFile) { out.push({ title: docs.get(area.current).title, dir: "" }); return out }
            const rel = area.currentPath.slice(p.root.length + 1).split("/")
            let acc = p.root
            for (const part of rel) {
                out.push({ title: part, dir: acc })
                acc += "/" + part
            }
            return out
        }
        readonly property var symbols: area.currentEditor && area.currentIsCode && area.currentEditor.revision >= 0
            ? Syntax.symbols(area.currentEditor.text) : []
        readonly property var currentSymbol: {
            const line = area.currentEditor ? area.currentEditor.cursorLine : 0
            let found = null
            for (const s of symbols) if (s.line <= line && s.kind !== "mark") found = s
            return found
        }

        Row {
            x: 10
            height: parent.height
            spacing: 2
            Repeater {
                model: jumpBar.crumbs
                delegate: Row {
                    id: crumb
                    required property var modelData
                    required property int index
                    height: jumpBar.height
                    spacing: 2
                    Symbol {
                        visible: crumb.index > 0
                        anchors.verticalCenter: parent.verticalCenter
                        name: "chevron-small-right"
                        size: 11
                        tone: "gray"
                    }
                    ToolbarButton {
                        id: crumbButton
                        anchors.verticalCenter: parent.verticalCenter
                        height: 22
                        text: crumb.modelData.title
                        symbol: crumb.modelData.project ? "hammer" : crumb.index === jumpBar.crumbs.length - 1 ? "code" : "folder"
                        symbolSize: 13
                        onClicked: {
                            // A crumb lists what sits beside it, as in Xcode's jump bar.
                            const dir = crumb.modelData.dir
                            if (!dir) return
                            const items = area.app.nodes.filter((n) => n.parent === dir).map((n) => ({
                                text: n.name, symbol: n.dir ? "folder" : "doc",
                                enabled: !n.dir, action: () => area.open(n.path, 0, 0) }))
                            if (items.length) area.menu.popup(crumbButton, 0, crumbButton.height + 4, items)
                        }
                    }
                }
            }
            Symbol {
                visible: area.currentIsCode
                anchors.verticalCenter: parent.verticalCenter
                name: "chevron-small-right"
                size: 11
                tone: "gray"
            }
            ToolbarButton {
                id: symbolCrumb
                visible: area.currentIsCode
                anchors.verticalCenter: parent.verticalCenter
                height: 22
                text: jumpBar.currentSymbol ? jumpBar.currentSymbol.name : "No Selection"
                onClicked: {
                    const items = jumpBar.symbols.map((s) => s.kind === "mark"
                        ? { header: s.name }
                        : { text: (s.kind === "func" || s.kind === "init" ? "    " : "") + s.name, checked: jumpBar.currentSymbol === s,
                            action: () => area.currentEditor.goTo(s.line, 1) })
                    area.menu.popup(symbolCrumb, 0, symbolCrumb.height + 4, items.length ? items : [{ text: "No Symbols", enabled: false }])
                }
            }
        }
    }

    // ----------------------------------------------------- find & replace
    Item {
        id: findBar
        y: jumpBar.y + (jumpBar.visible ? jumpBar.height : 0)
        width: parent.width
        height: area.findVisible ? (area.replaceVisible ? 78 : 42) : 0
        visible: area.findVisible
        clip: true
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.separator }
        Row {
            x: 10; y: 6
            spacing: 6
            Segmented {
                id: findMode
                anchors.verticalCenter: parent.verticalCenter
                options: ["Find", "Replace"]
                current: area.replaceVisible ? 1 : 0
                onPicked: (i) => area.replaceVisible = i === 1
            }
            TextField {
                id: findField
                width: Math.max(180, findBar.width - 470)
                height: 30
                search: true
                placeholder: "Find"
                onTextChanged: if (area.currentEditor) area.currentEditor.findNext(text, true, matchCase.checked)
                onAccepted: area.findNext(true)
                input.Keys.onEscapePressed: area.hideFind()
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 74
                text: area.currentEditor && findField.text ? area.currentEditor.countMatches(findField.text, matchCase.checked) + " matches" : ""
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: 11 }
            }
            ToolbarButton { id: matchCase; anchors.verticalCenter: parent.verticalCenter; text: "Aa"; onClicked: checked = !checked }
            ToolbarPill {
                anchors.verticalCenter: parent.verticalCenter
                ToolbarButton { symbol: "chevron-left"; onClicked: area.findNext(false) }
                ToolbarButton { symbol: "chevron-right"; onClicked: area.findNext(true) }
            }
            Button { anchors.verticalCenter: parent.verticalCenter; text: "Done"; onClicked: area.hideFind() }
        }
        Row {
            visible: area.replaceVisible
            x: 10 + findMode.width + 6; y: 42
            spacing: 6
            TextField { id: replaceField; width: Math.max(180, findBar.width - 470); height: 30; placeholder: "Replace" }
            Button {
                anchors.verticalCenter: parent.verticalCenter
                text: "Replace"
                onClicked: if (area.currentEditor) area.currentEditor.replaceSelection(findField.text, replaceField.text, matchCase.checked)
            }
            Button {
                anchors.verticalCenter: parent.verticalCenter
                text: "All"
                onClicked: if (area.currentEditor) area.currentEditor.replaceAll(findField.text, replaceField.text, matchCase.checked)
            }
        }
    }

    // ------------------------------------------------------------- editors
    Item {
        id: editorStack
        width: parent.width
        y: findBar.y + findBar.height
        height: parent.height - y

        EmptyState {
            anchors.fill: parent
            visible: docs.count === 0
            symbol: "code"
            title: "No Editor"
            text: "Select a file in the Project navigator, or press ⌘⇧O to open one quickly."
        }

        Repeater {
            id: editors
            model: docs
            delegate: Loader {
                id: holder
                required property int index
                required property string path
                required property string kind
                required property bool locked
                required property string content
                required property string lang
                anchors.fill: parent
                visible: index === area.current
                sourceComponent: kind === "design" ? designComponent : codeComponent
                onVisibleChanged: if (visible && item && item.editor) item.editor.forceActiveFocus()

                Connections {
                    target: holder.item
                    function onRevisionChanged() {
                        const dirty = area.isFileKind(holder.kind) && holder.item.text !== holder.item.savedText
                        if (docs.get(holder.index) && docs.get(holder.index).dirty !== dirty) docs.setProperty(holder.index, "dirty", dirty)
                    }
                    function onSavedTextChanged() {
                        if (docs.get(holder.index)) docs.setProperty(holder.index, "dirty", holder.item.text !== holder.item.savedText)
                    }
                }

                Component {
                    id: designComponent
                    DesignEditor {
                        path: holder.path
                        readOnly: holder.locked
                        menu: area.menu
                        overlay: area.overlay
                        backend: area.backend
                        app: area.app
                        Component.onCompleted: load(holder.content)
                        onOpenAsText: area.open(holder.path, 0, 0, true)
                        onShowCode: (title, code) => area.openLog(title, code, "js")
                        onError: (title, message) => area.error(title, message)
                    }
                }

                Component {
                    id: codeComponent
                    CodeEditor {
                        id: ed
                        property string savedText: ""
                        readOnly: holder.locked
                        language: holder.kind === "log" ? (holder.lang || "plain") : Syntax.languageFor(holder.path)
                        fontSize: area.app.settings.fontSize || 13
                        tabWidth: area.app.settings.tabWidth || 4
                        showMinimap: holder.kind === "file" && area.app.settings.showMinimap !== false
                        highlightText: area.findVisible ? findField.text : ""
                        caseSensitive: matchCase.checked
                        issues: area.app.issues.filter((i) => i.path === holder.path && i.line > 0)
                        Component.onCompleted: {
                            editor.text = holder.content
                            savedText = editor.text
                            editor.cursorPosition = 0
                            const jump = area.pendingJump
                            if (jump && jump.path === holder.path) {
                                area.pendingJump = null
                                Qt.callLater(() => ed.goTo(jump.line, jump.column))
                            }
                            if (holder.visible) editor.forceActiveFocus()
                        }
                        onContextMenuRequested: (x, y) => area.menu.popup(ed, x, y, [
                            { text: "Cut", shortcut: "⌘X", enabled: !ed.readOnly && ed.editor.selectedText.length > 0, action: () => ed.editor.cut() },
                            { text: "Copy", shortcut: "⌘C", enabled: ed.editor.selectedText.length > 0, action: () => ed.editor.copy() },
                            { text: "Paste", shortcut: "⌘V", enabled: !ed.readOnly && ed.editor.canPaste, action: () => ed.editor.paste() },
                            { separator: true },
                            { text: "Comment Selection", shortcut: "⌘/", enabled: !ed.readOnly, action: () => ed.toggleComment() },
                            { text: "Shift Right", shortcut: "⌘]", enabled: !ed.readOnly, action: () => ed.shiftLines(true) },
                            { text: "Shift Left", shortcut: "⌘[", enabled: !ed.readOnly, action: () => ed.shiftLines(false) },
                            { separator: true },
                            { text: "Find in Project…", shortcut: "⇧⌘F", action: () => area.findInProjectRequested(ed.editor.selectedText) },
                        ].concat(holder.path.endsWith(".lcdesign") ? [{ separator: true }, { text: "Open in App Designer", action: () => { area.closeAt(holder.index, false); Qt.callLater(() => area.open(holder.path, 0, 0)) } }] : []))
                    }
                }
            }
        }
    }
}
