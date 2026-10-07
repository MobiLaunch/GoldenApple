// The note: rich text over Markdown, saved as you type. The first line is the
// note's title (styled as Title in a new note, as on the Mac) and the file is
// renamed to follow it.
//
// Keys, as in Notes (⌘ is Ctrl here): B/I/U bold, italic, underline, ⇧X
// strikethrough; ⇧T title, ⇧H heading, ⇧J subheading, ⇧B body, ⇧L checklist,
// ⇧7 bulleted and ⇧9 numbered list. Click a checkbox to tick it.
import Quickshell
import Quickshell.Io
import QtQuick
import "../lib" as Shared
import "../lib/theme"
import "md.js" as Md

Item {
    id: ed
    property string path
    property real mtime: 0
    property bool dirty: false
    property string saveError: ""
    property bool writeOk: false
    signal saveFailed()
    property var taken: []              // paths of other notes (renames never overwrite one)
    signal saved(string path, string newPath, string title, string preview)
    signal menuRequested(var items, Item item, real x, real y)

    property string loadedPath: ""
    property bool loading: false
    property string lastSaved: ""
    property bool fresh: false          // a new note: its first line becomes the title
    property bool renaming: false       // the file just moved to follow the title
    property int bodyNext: -1           // block that becomes body text once typed in

    Connections {
        target: Qt.application
        function onAboutToQuit() { ed.flush() }
    }

    function markdown() { return edit.getFormattedText(0, edit.length) }
    function writingTools() { edit.openWritingTools() }
    function flush() { return !dirty || !loadedPath || save() }
    function startNew(p) { fresh = true }

    onPathChanged: {
        if (path === loadedPath) return               // our own rename
        saveTimer.stop()
        if (dirty && loadedPath && !save()) return
        renaming = false
        loadedPath = path
        dirty = false
        if (!path) { loading = true; edit.text = ""; loading = false; return }
        file.path = path
        file.reload()
    }

    FileView {
        id: file
        printErrors: false
        blockWrites: true                             // a save is on disk before the next step
        onLoaded: {
            if (ed.renaming) { ed.renaming = false; return }
            const t = text()
            if (t === ed.lastSaved && ed.markdown() === t) return    // our own save
            ed.loading = true
            edit.text = t
            ed.loading = false
            ed.fresh = !t.trim()
            ed.lastSaved = t
            edit.cursorPosition = 0
            scroller.contentY = 0
            if (ed.fresh) edit.forceActiveFocus()
        }
        onLoadFailed: {
            if (ed.renaming) { ed.renaming = false; return }
            ed.loading = true; edit.text = ""; ed.loading = false
            ed.fresh = true
            edit.forceActiveFocus()
        }
    }

    function save() {
        saveTimer.stop()
        if (!dirty || !loadedPath || loading) return !dirty
        const md = markdown()
        const lines = md.split("\n").filter((l) => l.trim())
        const clean = (s) => s.replace(/^[#>*+ -]+/, "").replace(/^\[[ xX]\]\s*/, "").replace(/\*\*|__|~~|`|\\/g, "").replace(/\]\([^)]*\)/g, "").replace(/\[/g, "").trim()
        const title = lines.length ? clean(lines[0]) : ""
        const preview = lines.slice(1).map(clean).join(" ").slice(0, 140)
        const from = loadedPath
        // Follow the title with the file name (never over another note).
        let to = from
        if (title) {
            const want = from.replace(/[^/]+$/, "") + Md.fileName(title)
            if (want !== from && !taken.includes(want)) to = want
        }
        // Write separately: changing the reader's path before a failed write
        // used to discard the draft and delete the original during a rename.
        writeOk = false
        writer.path = to
        writer.setText(md)
        if (!writeOk) {
            saveError = "Could not save this note. Check disk space and folder permissions. Your draft is still open."
            saveFailed()
            return false
        }
        saveError = ""
        lastSaved = md
        if (to !== from) { renaming = true; loadedPath = to; file.path = to }
        if (to !== from) Quickshell.execDetached(["rm", "-f", "--", from])
        dirty = false
        saved(from, to, title, preview)
        return true
    }
    FileView {
        id: writer
        preload: false
        blockWrites: true
        atomicWrites: true
        onSaved: ed.writeOk = true
        onSaveFailed: ed.writeOk = false
    }
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 8 }
        height: errorLabel.implicitHeight + 20
        visible: !!ed.saveError
        color: Theme.dark ? "#502a23" : "#fff0e8"
        radius: 8; z: 20
        Text {
            id: errorLabel
            anchors { fill: parent; margins: 10 }
            text: ed.saveError; wrapMode: Text.Wrap
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
        }
    }
    Timer { id: saveTimer; interval: 700; onTriggered: ed.save() }

    function changed() {
        if (loading) return
        dirty = true
        saveTimer.restart()
    }
    function block() { return Md.blockAt(edit.getText(0, edit.cursorPosition)) }
    function setStyle(style) {
        const pos = edit.cursorPosition
        const md = Md.setStyle(markdown(), block(), style)
        loading = true
        edit.text = md
        loading = false
        edit.cursorPosition = Math.min(pos, edit.length)
        edit.forceActiveFocus()
        changed()
    }
    function toggleFont(prop) {
        const f = edit.cursorSelection.font
        f[prop] = !f[prop]
        edit.cursorSelection.font = f
        changed()
    }
    function formatMenu(item) {
        const style = Md.styleOf(markdown(), block())
        const mark = (s) => style === s
        menuRequested([
            { text: "Writing Tools…", action: () => writingTools() },
            { separator: true },
            { text: "Title", checked: mark("title"), action: () => setStyle("title") },
            { text: "Heading", checked: mark("heading"), action: () => setStyle("heading") },
            { text: "Subheading", checked: mark("subheading"), action: () => setStyle("subheading") },
            { text: "Body", checked: mark("body"), action: () => setStyle("body") },
            { separator: true },
            { text: "Bulleted List", checked: mark("bullet"), action: () => setStyle("bullet") },
            { text: "Numbered List", checked: mark("number"), action: () => setStyle("number") },
            { text: "Checklist", checked: style === "check" || style === "done", action: () => setStyle("check") },
            { separator: true },
            { text: "Bold", action: () => toggleFont("bold") },
            { text: "Italic", action: () => toggleFont("italic") },
            { text: "Underline", action: () => toggleFont("underline") },
            { text: "Strikethrough", action: () => toggleFont("strikeout") },
        ], item, 0, item.height + 6)
    }

    Flickable {
        id: scroller
        anchors.fill: parent
        contentHeight: column.height + 60
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        function ensureVisible(r) {
            const top = r.y + column.y + edit.y, bottom = top + r.height
            if (top < contentY) contentY = top - 8
            else if (bottom > contentY + height) contentY = bottom - height + 24
        }

        Column {
            id: column
            x: 26; y: 6
            width: scroller.width - 52
            spacing: 10
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                visible: !!ed.path
                text: ed.mtime ? new Date(ed.mtime * 1000).toLocaleString(Qt.locale(), "d MMMM yyyy 'at' " + Qt.locale().timeFormat(Locale.ShortFormat)) : ""
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: Theme.fs(11); weight: Font.Medium }
            }
            Shared.TextArea {
                id: edit
                width: parent.width
                visible: !!ed.path
                textFormat: TextEdit.MarkdownText
                writingContext: ed.loadedPath
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                persistentSelection: true
                color: Theme.label
                selectionColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.3)
                selectedTextColor: Theme.label
                font { family: Theme.fontUi; pixelSize: Theme.fs(14) }
                onTextChanged: {
                    if (ed.loading) return
                    // A new note's first line is its title.
                    if (ed.fresh && edit.length > 0) {
                        ed.fresh = false
                        if (Md.styleOf(ed.markdown(), 0) === "body") { ed.setStyle("title"); return }
                    }
                    if (ed.bodyNext >= 0) {
                        const b = ed.block()
                        if (b === ed.bodyNext && edit.cursorPosition > Md.lineStart(edit.getText(0, edit.cursorPosition))) {
                            ed.bodyNext = -1
                            if (Md.styleOf(ed.markdown(), b) !== "body") { ed.setStyle("body"); return }
                        } else if (b !== ed.bodyNext && b !== ed.bodyNext - 1) ed.bodyNext = -1
                    }
                    ed.changed()
                }
                onCursorRectangleChanged: scroller.ensureVisible(cursorRectangle)
                onLinkActivated: (link) => Qt.openUrlExternally(link)

                // Return at the end of a title or heading continues in body text.
                // Return after a title or heading continues in body text: Qt keeps the
                // heading for the new line, so it's changed once the line has text
                // (an empty line wouldn't survive the round trip through Markdown).
                Keys.onReturnPressed: (e) => {
                    const style = Md.styleOf(ed.markdown(), ed.block())
                    ed.bodyNext = style === "title" || style === "heading" || style === "subheading" ? ed.block() + 1 : -1
                    e.accepted = false
                }
                Keys.onPressed: (e) => {
                    const ctrl = e.modifiers & Qt.ControlModifier, shift = e.modifiers & Qt.ShiftModifier
                    if (!ctrl) return
                    const k = e.key
                    if (!shift && k === Qt.Key_B) ed.toggleFont("bold")
                    else if (!shift && k === Qt.Key_I) ed.toggleFont("italic")
                    else if (!shift && k === Qt.Key_U) ed.toggleFont("underline")
                    else if (shift && k === Qt.Key_X) ed.toggleFont("strikeout")
                    else if (shift && k === Qt.Key_T) ed.setStyle("title")
                    else if (shift && k === Qt.Key_H) ed.setStyle("heading")
                    else if (shift && k === Qt.Key_J) ed.setStyle("subheading")
                    else if (shift && k === Qt.Key_B) ed.setStyle("body")
                    else if (shift && k === Qt.Key_L) ed.setStyle("check")
                    else if (shift && (k === Qt.Key_7 || k === Qt.Key_Ampersand)) ed.setStyle("bullet")
                    else if (shift && (k === Qt.Key_9 || k === Qt.Key_ParenLeft)) ed.setStyle("number")
                    else return
                    e.accepted = true
                }

                // Ticking a checkbox: a click left of a checklist item's text.
                TapHandler {
                    onTapped: (p) => {
                        const pos = edit.positionAt(p.position.x, p.position.y)
                        const before = edit.getText(0, pos)
                        const blockStart = Md.lineStart(before)
                        const b = Md.blockAt(before)
                        const style = Md.styleOf(ed.markdown(), b)
                        if ((style === "check" || style === "done") && p.position.x < edit.positionToRectangle(blockStart).x - 2) {
                            const md = Md.toggleCheck(ed.markdown(), b)
                            ed.loading = true
                            edit.text = md
                            ed.loading = false
                            edit.cursorPosition = Math.min(pos, edit.length)
                            ed.changed()
                        }
                    }
                }
            }
        }
        MouseArea {
            // Clicking below the text puts the cursor at the end.
            y: column.y + column.height; width: parent.width; height: Math.max(0, scroller.height - y + scroller.contentY)
            onClicked: { edit.forceActiveFocus(); edit.cursorPosition = edit.length }
        }
    }
}
