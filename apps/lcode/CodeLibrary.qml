// The Library for code (⇧⌘L, or + while editing): snippets — built in and
// your own — CitronOS's symbols and the system colours, to drop in at the
// cursor. Make a snippet from the selection with “New Snippet”.
import QtQuick
import "../lib"
import "../lib/theme"
import "../lib/kit/kit.js" as K
import "completion.js" as Completion
import "design"

Popover {
    id: lib
    property var app
    property var backend
    property var editorArea
    property int tab: 0                      // snippets, symbols, colours
    property var symbolNames: []
    property bool creating: false
    panelWidth: 380
    panelHeight: 470

    readonly property string language: editorArea && editorArea.currentEditor ? editorArea.currentEditor.language : "plain"
    readonly property string query: search.text.trim().toLowerCase()
    readonly property var snippets: Completion.snippetsFor(language, app.settings.userSnippets || [])
        .filter((s) => !query || s.title.toLowerCase().includes(query) || s.trigger.toLowerCase().includes(query))
    readonly property var symbols: symbolNames.filter((n) => !query || n.includes(query))
    readonly property var colors: K.SYSTEM_NAMES.filter((n) => !query || n.includes(query))

    onVisibleChanged: if (visible) {
        creating = false
        search.text = ""
        if (!symbolNames.length) backend.call("symbols", {}, (r) => { if (r.ok) lib.symbolNames = r.symbols })
        Qt.callLater(() => search.input.forceActiveFocus())
    }

    function insertSnippet(s) { close(); editorArea.insertSnippet(s.body) }
    function insertSymbol(name) { close(); editorArea.insertText("\"" + name + "\"") }
    function insertColor(name) {
        close()
        const env = { dark: Theme.dark }
        // QML uses the hex value; other languages too, as a string.
        editorArea.insertText("\"" + K.color(name, env) + "\"")
    }
    function startSnippet() {
        const ed = editorArea.currentEditor
        titleField.text = ""
        triggerField.text = ""
        bodyField.text = ed && ed.editor.selectedText ? ed.editor.selectedText.split(String.fromCharCode(0x2029)).join("\n") : ""
        creating = true
        Qt.callLater(() => titleField.input.forceActiveFocus())
    }
    function saveSnippet() {
        const title = titleField.text.trim(), body = bodyField.text
        if (!title || !body.trim()) return
        // Store with four-space indentation, which snippets expand from.
        const unit = editorArea.currentEditor ? editorArea.currentEditor.indentUnit() : "    "
        const normalised = body.split("\n").map((l) => { let n = 0; while (l.startsWith(unit, n * unit.length)) n++; return "    ".repeat(n) + l.slice(n * unit.length) })
        const trigger = (triggerField.text.trim() || title).replace(/[^A-Za-z0-9_]/g, "").toLowerCase() || "snippet"
        const snippet = { id: "snippet-" + Date.now().toString(36), title: title, trigger: trigger, language: language, body: normalised.join("\n") }
        app.saveSettings({ userSnippets: (app.settings.userSnippets || []).concat([snippet]) })
        creating = false
    }
    function deleteSnippet(id) {
        app.saveSettings({ userSnippets: (app.settings.userSnippets || []).filter((s) => s.id !== id) })
    }

    Column {
        width: parent.width
        spacing: 10
        visible: !lib.creating
        Row {
            spacing: 8
            Segmented {
                options: ["Snippets", "Symbols", "Colors"]
                current: lib.tab
                onPicked: (i) => lib.tab = i
            }
            Button {
                visible: lib.tab === 0
                text: "New Snippet"
                symbol: "plus"
                onClicked: lib.startSnippet()
            }
        }
        TextField {
            id: search
            width: parent.width
            height: 28
            search: true
            placeholder: lib.tab === 0 ? "Search " + (Completion.LANGUAGE_NAMES[lib.language] || "") + " snippets" : lib.tab === 1 ? "Search symbols" : "Search colors"
            onAccepted: {
                if (lib.tab === 0 && lib.snippets.length) lib.insertSnippet(lib.snippets[0])
                else if (lib.tab === 1 && lib.symbols.length) lib.insertSymbol(lib.symbols[0])
                else if (lib.tab === 2 && lib.colors.length) lib.insertColor(lib.colors[0])
            }
        }

        // Snippets.
        ListView {
            visible: lib.tab === 0
            width: parent.width
            height: 370
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: lib.snippets
            delegate: Rectangle {
                id: snip
                required property var modelData
                width: ListView.view.width
                height: 54
                radius: 8
                color: snipHover.hovered ? (Theme.dark ? "#18ffffff" : "#0c000000") : "transparent"
                Rectangle {
                    x: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 34; height: 34
                    radius: 8
                    color: snip.modelData.own ? Theme.accent : "#6e7681"
                    Symbol { anchors.centerIn: parent; name: "curlybraces"; size: 18; tone: "white" }
                }
                Column {
                    x: 50
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x - 36
                    spacing: 2
                    Row {
                        spacing: 6
                        Text { text: snip.modelData.title; color: Theme.label; font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold } }
                        Text { anchors.baseline: parent.children[0].baseline; text: snip.modelData.trigger; color: Theme.secondaryLabel; font { family: "monospace"; pixelSize: 11 } }
                    }
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: snip.modelData.body.split("\n")[0].replace(/<#([^#\n]*)#>/g, "$1")
                        color: Theme.secondaryLabel
                        font { family: "monospace"; pixelSize: 11 }
                    }
                }
                ToolbarButton {
                    visible: !!snip.modelData.own && snipHover.hovered
                    anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                    symbol: "trash"
                    symbolSize: 13
                    Accessible.name: "Delete Snippet"
                    onClicked: lib.deleteSnippet(snip.modelData.id)
                }
                HoverHandler { id: snipHover }
                TapHandler { onTapped: lib.insertSnippet(snip.modelData) }
            }
            Text {
                anchors.centerIn: parent
                visible: parent.count === 0
                text: "No snippets for this language yet"
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: 12 }
            }
        }

        // Symbols.
        GridView {
            visible: lib.tab === 1
            width: parent.width
            height: 370
            clip: true
            cellWidth: width / 6
            cellHeight: 62
            boundsBehavior: Flickable.StopAtBounds
            model: lib.symbols
            delegate: Rectangle {
                id: sym
                required property string modelData
                width: GridView.view.cellWidth - 4
                height: 58
                radius: 8
                color: symHover.hovered ? (Theme.dark ? "#18ffffff" : "#0c000000") : "transparent"
                Symbol { anchors.horizontalCenter: parent.horizontalCenter; y: 8; name: sym.modelData; size: 22 }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 38
                    width: parent.width - 4
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: sym.modelData
                    color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: 9 }
                }
                HoverHandler { id: symHover }
                TapHandler { onTapped: lib.insertSymbol(sym.modelData) }
            }
        }

        // Colours.
        GridView {
            visible: lib.tab === 2
            width: parent.width
            height: 370
            clip: true
            cellWidth: width / 4
            cellHeight: 70
            boundsBehavior: Flickable.StopAtBounds
            model: lib.colors
            delegate: Rectangle {
                id: col
                required property string modelData
                width: GridView.view.cellWidth - 4
                height: 66
                radius: 8
                color: colHover.hovered ? (Theme.dark ? "#18ffffff" : "#0c000000") : "transparent"
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 8
                    width: 30; height: 30
                    radius: 15
                    color: K.color(col.modelData, { dark: Theme.dark })
                    border { width: 1; color: Theme.separator }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 44
                    width: parent.width - 4
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: col.modelData
                    color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: 10 }
                }
                HoverHandler { id: colHover }
                TapHandler { onTapped: lib.insertColor(col.modelData) }
            }
        }
    }

    // A new snippet.
    Column {
        width: parent.width
        spacing: 10
        visible: lib.creating
        Text {
            text: "New " + (Completion.LANGUAGE_NAMES[lib.language] || "") + " Snippet"
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: 14; weight: Font.Bold }
        }
        TextField { id: titleField; width: parent.width; height: 28; placeholder: "Title, like “Fetch JSON”" }
        TextField { id: triggerField; width: parent.width; height: 28; placeholder: "Completion, like fetchjson (type it to get the snippet)" }
        Text {
            width: parent.width
            wrapMode: Text.Wrap
            text: "Write <#name#> where you'd like a placeholder: Tab goes from one to the next."
            color: Theme.secondaryLabel
            font { family: Theme.fontUi; pixelSize: 11 }
        }
        Rectangle {
            width: parent.width
            height: 220
            radius: 8
            color: lib.app.editorColors.background
            border { width: 1; color: Theme.separator }
            clip: true
            CodeEditor {
                id: bodyField
                anchors { fill: parent; margins: 1 }
                language: lib.language
                colors: lib.app.editorColors
                showMinimap: false
                showLineNumbers: false
                fontFamily: lib.app.settings.fontFamily || "monospace"
                fontSize: 12
            }
        }
        Row {
            anchors.right: parent.right
            spacing: 8
            Button { text: "Cancel"; onClicked: lib.creating = false }
            Button { text: "Save Snippet"; prominent: true; enabled: titleField.text.trim().length > 0; onClicked: lib.saveSnippet() }
        }
    }
}
