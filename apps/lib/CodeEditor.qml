// Shared source-code editor (LCode, and any app that shows or edits code):
// monospaced, coloured like the classic Apple IDE themes, with line numbers,
// the current line, per-line issues (gutter mark, tint and banner), find
// matches and a minimap.
//   CodeEditor { text: "…"; language: Syntax.languageFor(path); issues: [{ line: 12, severity: "error", message: "…" }] }
//
// The text is edited in a TextEdit whose own glyphs are transparent; the
// coloured text is drawn over it, one Text per visible line, from the line
// tokenizer in syntax.js. Every line has the same height, so the gutter,
// tints, banners and matches are placed arithmetically.
import QtQuick
import "theme"
import "syntax.js" as Syntax

Item {
    id: root

    property alias text: edit.text
    property string language: "plain"
    property bool readOnly: false
    property real fontSize: 13
    property int tabWidth: 4
    property bool insertSpaces: true
    property bool showMinimap: true
    property var issues: []                 // [{ line, severity: "error" | "warning", message }]
    property string highlightText: ""       // find matches to mark
    property bool caseSensitive: false
    // A colour theme from Syntax.THEMES (or a custom one); null follows the
    // system appearance with the default themes.
    property var colors: null
    property string fontFamily: "monospace"
    property bool showLineNumbers: true
    property bool highlightCurrentLine: true
    property bool autoClose: true           // type ( [ { " and get the closing one too
    readonly property var editorPalette: colors || (Theme.dark ? Syntax.THEMES[1] : Syntax.THEMES[0])
    readonly property bool darkColors: editorPalette.dark === undefined ? Theme.dark : !!editorPalette.dark
    readonly property alias editor: edit
    readonly property int cursorLine: Math.floor(edit.cursorRectangle.y / lineHeight + 0.5) + 1
    readonly property int cursorColumn: edit.cursorPosition - edit.positionAt(0, edit.cursorRectangle.y + lineHeight / 2) + 1
    readonly property int lineCount: lines.length
    readonly property color background: editorPalette.background || (Theme.dark ? "#1f1f24" : "#ffffff")
    signal contextMenuRequested(real x, real y)
    // After a character (or "\b" for Backspace) has gone into the text: for
    // completion as you type.
    signal typed(string text)
    // Sees keys first while it returns true (a completion list, say).
    property var keyFilter: null

    property var lines: [""]
    property var tokenStates: [0]
    property int revision: 0
    readonly property real lineHeight: edit.lineCount > 0 && edit.contentHeight > 0 ? edit.contentHeight / edit.lineCount : metrics.height
    readonly property real charWidth: widthProbe.advanceWidth / 64
    readonly property real gutterWidth: showLineNumbers ? Math.max(3, String(lines.length).length) * charWidth + 30 : 22
    readonly property real minimapWidth: showMinimap ? 92 : 0
    readonly property real topPad: 6
    readonly property int firstVisible: Math.max(0, Math.floor((view.contentY - topPad) / lineHeight) - 1)
    readonly property int visibleCount: Math.max(0, Math.min(lines.length - firstVisible, Math.ceil(view.height / lineHeight) + 3))

    function reparse() {
        lines = edit.text.split("\n")
        tokenStates = Syntax.lineStates(lines, language)
        revision++
    }
    onLanguageChanged: reparse()
    Component.onCompleted: reparse()

    function lineHtml(i) {
        return i < lines.length ? Syntax.html(lines[i], tokenStates[i] || 0, language, editorPalette, tabWidth) : ""
    }
    function visualLength(i) { return i < lines.length ? Syntax.expandTabs(lines[i], tabWidth).length : 0 }
    function lineY(line) { return topPad + (line - 1) * lineHeight }   // 1-based
    function lineStart(line) {                                      // 1-based line → position
        let pos = 0
        for (let i = 0; i < Math.min(line - 1, lines.length); i++) pos += lines[i].length + 1
        return pos
    }

    function goTo(line, column) {
        const l = Math.max(1, Math.min(line, lines.length))
        const start = lineStart(l)
        edit.cursorPosition = Math.min(start + Math.max(0, (column || 1) - 1), start + lines[l - 1].length)
        view.contentY = Math.max(0, Math.min(lineY(l) - view.height * 0.3, view.contentHeight - view.height))
        edit.forceActiveFocus()
    }

    function ensureCursorVisible() {
        const r = edit.cursorRectangle
        const y = r.y + topPad
        if (y < view.contentY) view.contentY = Math.max(0, y - lineHeight)
        else if (y + r.height > view.contentY + view.height) view.contentY = y + r.height - view.height + lineHeight
        const x = r.x + edit.x
        if (x < view.contentX + edit.x) view.contentX = Math.max(0, x - edit.x - 40)
        else if (x > view.contentX + view.width - 20) view.contentX = x - view.width + 60
    }

    // ---- Editing commands (all through insert/remove, so they undo) -------

    function selectedLineRange() {
        const a = Math.min(edit.selectionStart, edit.selectionEnd), b = Math.max(edit.selectionStart, edit.selectionEnd)
        const first = edit.text.lastIndexOf("\n", a - 1) + 1
        let endAt = b > a && edit.text[b - 1] === "\n" ? b - 1 : b
        let last = edit.text.indexOf("\n", endAt)
        if (last < 0) last = edit.text.length
        return [first, last]
    }

    function replaceRange(start, end, replacement, select) {
        edit.remove(start, end)
        edit.insert(start, replacement)
        if (select) edit.select(start, start + replacement.length)
    }

    function toggleComment() {
        if (readOnly) return
        const [start, end] = selectedLineRange()
        const lang = language
        replaceRange(start, end, Syntax.toggleComment(edit.text.slice(start, end).split("\n"), lang).join("\n"), true)
    }

    function indentUnit() { return insertSpaces ? " ".repeat(tabWidth) : "\t" }

    function shiftLines(right) {
        const [start, end] = selectedLineRange()
        const unit = indentUnit()
        const shifted = edit.text.slice(start, end).split("\n").map((l) => {
            if (right) return l.length ? unit + l : l
            if (l.startsWith("\t")) return l.slice(1)
            let n = 0
            while (n < tabWidth && l[n] === " ") n++
            return l.slice(n)
        })
        replaceRange(start, end, shifted.join("\n"), true)
    }

    function newline() {
        const pos = edit.cursorPosition
        const lineStartPos = edit.text.lastIndexOf("\n", pos - 1) + 1
        const before = edit.text.slice(lineStartPos, pos)
        const indent = before.match(/^[ \t]*/)[0]
        const opener = /[{(\[]\s*$/.test(before)
        const closer = /^\s*[})\]]/.test(edit.text.slice(pos, edit.text.indexOf("\n", pos) < 0 ? undefined : edit.text.indexOf("\n", pos)))
        if (edit.selectedText.length) edit.remove(edit.selectionStart, edit.selectionEnd)
        if (opener && closer) {
            edit.insert(edit.cursorPosition, "\n" + indent + indentUnit() + "\n" + indent)
            edit.cursorPosition -= indent.length + 1
        } else {
            edit.insert(edit.cursorPosition, "\n" + indent + (opener ? indentUnit() : ""))
        }
    }

    function closeBrace(ch) {
        const pos = edit.cursorPosition
        const lineStartPos = edit.text.lastIndexOf("\n", pos - 1) + 1
        const before = edit.text.slice(lineStartPos, pos)
        if (before.length && !before.trim().length) {
            // Typing } on a blank line lines it up with the block it closes.
            const outdented = before.endsWith("\t") ? before.slice(0, -1) : before.slice(0, Math.max(0, before.length - tabWidth))
            edit.remove(lineStartPos, pos)
            edit.insert(lineStartPos, outdented + ch)
        } else {
            edit.insert(pos, ch)
        }
    }

    // Tidy up before saving: trailing spaces and tabs off every line but the
    // cursor's (edited in place, so undo and the cursor survive), and a
    // newline at the end.
    function trimTrailingWhitespace() {
        if (readOnly) return
        const ls = edit.text.split("\n")
        let pos = edit.text.length
        for (let i = ls.length - 1; i >= 0; i--) {
            pos -= ls[i].length
            const m = /[ \t]+$/.exec(ls[i])
            if (m && i !== cursorLine - 1) edit.remove(pos + m.index, pos + ls[i].length)
            pos -= 1
        }
    }
    function ensureFinalNewline() {
        if (!readOnly && edit.length > 0 && !edit.text.endsWith("\n")) {
            const cursor = edit.cursorPosition
            edit.insert(edit.length, "\n")
            edit.cursorPosition = cursor
        }
    }

    // Auto-closing pairs: an opener types its closer too (or wraps the
    // selection); typing a closer that's already next steps over it.
    readonly property var pairs: ({ "(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'" })
    function typePair(ch) {
        if (!ch || ch.length !== 1) return false
        const pos = edit.cursorPosition
        const next = edit.text.charAt(pos)
        const prev = pos > 0 ? edit.text.charAt(pos - 1) : ""
        const quote = ch === "\"" || ch === "'"
        if ((ch === ")" || ch === "]" || ch === "}" || quote) && next === ch && !edit.selectedText.length) {
            edit.cursorPosition = pos + 1
            return true
        }
        const close = pairs[ch]
        if (!close) return false
        if (quote && (/\w/.test(prev) || (ch === "'" && (language === "rust" || language === "plain")))) return false
        if (edit.selectedText.length && !edit.selectedText.includes("\n")) {
            const start = edit.selectionStart, end = edit.selectionEnd, inner = edit.selectedText
            edit.remove(start, end)
            edit.insert(start, ch + inner + close)
            edit.select(start + 1, start + 1 + inner.length)
            return true
        }
        if (next && !/[\s)\]},;:]/.test(next)) return false
        edit.insert(pos, ch + close)
        edit.cursorPosition = pos + 1
        return true
    }
    function deletePair() {
        const pos = edit.cursorPosition
        if (edit.selectedText.length || pos < 1) return false
        const prev = edit.text.charAt(pos - 1)
        if (!pairs[prev] || edit.text.charAt(pos) !== pairs[prev]) return false
        edit.remove(pos - 1, pos + 1)
        return true
    }

    // Find: select the next (or previous) match after the selection.
    function findNext(query, forward, matchCase) {
        if (!query) return false
        const hay = matchCase ? edit.text : edit.text.toLowerCase()
        const needle = matchCase ? query : query.toLowerCase()
        const from = forward ? Math.max(edit.selectionStart, edit.selectionEnd) : Math.min(edit.selectionStart, edit.selectionEnd)
        let at = forward ? hay.indexOf(needle, from) : hay.lastIndexOf(needle, from - 1)
        if (at < 0) at = forward ? hay.indexOf(needle) : hay.lastIndexOf(needle)   // wrap around
        if (at < 0) return false
        edit.select(at, at + needle.length)
        ensureCursorVisible()
        return true
    }
    function countMatches(query, matchCase) {
        if (!query) return 0
        const hay = matchCase ? edit.text : edit.text.toLowerCase()
        const needle = matchCase ? query : query.toLowerCase()
        let n = 0, at = hay.indexOf(needle)
        while (at >= 0) { n++; at = hay.indexOf(needle, at + needle.length) }
        return n
    }
    function replaceSelection(query, replacement, matchCase) {
        const sel = edit.selectedText
        if (sel.length && (matchCase ? sel === query : sel.toLowerCase() === query.toLowerCase()))
            replaceRange(edit.selectionStart, edit.selectionEnd, replacement, false)
        findNext(query, true, matchCase)
    }
    function replaceAll(query, replacement, matchCase) {
        if (!query) return 0
        const flags = matchCase ? "g" : "gi"
        const escaped = query.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
        const count = countMatches(query, matchCase)
        if (count) replaceRange(0, edit.length, edit.text.replace(new RegExp(escaped, flags), () => replacement), false)
        return count
    }

    // Matches in the visible lines, for the find highlight.
    // Placeholders: <#name#> tokens, as in Xcode snippets. Tab selects the
    // next one; clicking into one selects it whole.
    readonly property bool hasPlaceholders: revision >= 0 && edit.text.indexOf("<#") >= 0
    function placeholderRanges(fromLine, toLine) {
        const out = []
        const re = /<#[^#\n]*#>/g
        for (let i = fromLine; i < toLine && i < lines.length; i++) {
            if (lines[i].indexOf("<#") < 0) continue
            let m
            re.lastIndex = 0
            while ((m = re.exec(lines[i])) !== null)
                out.push({ line: i + 1, start: lineStart(i + 1) + m.index, end: lineStart(i + 1) + m.index + m[0].length })
        }
        return out
    }
    function selectPlaceholder(backwards) {
        const all = placeholderRanges(0, lines.length)
        if (!all.length) return false
        const pos = backwards ? edit.selectionStart : edit.selectionEnd
        let pick = null
        if (backwards) { for (let i = all.length - 1; i >= 0 && !pick; i--) if (all[i].end <= pos && !(all[i].start === edit.selectionStart)) pick = all[i] }
        else { for (const r of all) if (!pick && r.start >= pos) pick = r }
        pick = pick || (backwards ? all[all.length - 1] : all[0])
        edit.select(pick.start, pick.end)
        return true
    }
    function selectPlaceholderAt(pos) {
        if (!hasPlaceholders || edit.selectedText.length) return
        const line = edit.text.lastIndexOf("\n", pos - 1) + 1
        const lineNo = edit.text.slice(0, line).split("\n").length
        for (const r of placeholderRanges(lineNo - 1, lineNo))
            if (pos > r.start && pos < r.end) { edit.select(r.start, r.end); return }
    }

    function visibleMatches() {
        const out = []
        if (!highlightText) return out
        const needle = caseSensitive ? highlightText : highlightText.toLowerCase()
        for (let i = firstVisible; i < firstVisible + visibleCount && i < lines.length; i++) {
            const hay = caseSensitive ? lines[i] : lines[i].toLowerCase()
            let at = hay.indexOf(needle)
            while (at >= 0) {
                out.push({ line: i + 1, start: lineStart(i + 1) + at, end: lineStart(i + 1) + at + needle.length })
                at = hay.indexOf(needle, at + Math.max(1, needle.length))
            }
        }
        return out
    }

    FontMetrics {
        id: metrics
        font: edit.font
    }
    TextMetrics {
        id: widthProbe
        font: edit.font
        text: "0".repeat(64)
    }
    // x of a document position, from the editor's own layout.
    function xAt(pos) { return edit.positionToRectangle(pos).x }

    Rectangle {
        anchors.fill: parent
        color: root.background
    }

    Flickable {
        id: view
        x: root.gutterWidth
        width: parent.width - root.gutterWidth - root.minimapWidth
        height: parent.height
        clip: true
        contentWidth: Math.max(width, edit.x + edit.contentWidth + 120)
        contentHeight: Math.max(height, root.topPad + edit.contentHeight + height * 0.5)
        boundsBehavior: Flickable.StopAtBounds
        // Dragging selects text; the wheel and touchpad scroll.
        acceptedButtons: Qt.NoButton

        // Current line.
        Rectangle {
            visible: root.highlightCurrentLine && edit.selectedText.length === 0
            x: 0
            y: root.lineY(root.cursorLine)
            width: view.contentWidth
            height: root.lineHeight
            color: root.editorPalette.currentLine || (root.darkColors ? "#23252b" : "#ecf5ff")
        }

        // Issue lines.
        Repeater {
            model: root.issues
            delegate: Rectangle {
                required property var modelData
                x: 0
                y: root.lineY(modelData.line)
                width: view.contentWidth
                height: root.lineHeight
                color: modelData.severity === "error" ? (root.darkColors ? "#33ff453a" : "#1fff3b30") : (root.darkColors ? "#2effd60a" : "#24ffcc00")
            }
        }

        // Find matches.
        Repeater {
            model: root.revision >= 0 ? root.visibleMatches() : []
            delegate: Rectangle {
                required property var modelData
                x: edit.x + root.xAt(modelData.start) - 1
                y: root.lineY(modelData.line)
                width: root.xAt(modelData.end) - root.xAt(modelData.start) + 2
                height: root.lineHeight
                radius: 3
                color: root.darkColors ? "#806a5a1e" : "#80ffe873"
            }
        }

        // Placeholder tokens.
        Repeater {
            model: root.hasPlaceholders ? root.placeholderRanges(root.firstVisible, root.firstVisible + root.visibleCount) : []
            delegate: Rectangle {
                required property var modelData
                x: edit.x + root.xAt(modelData.start) + root.charWidth * 0.5
                y: root.lineY(modelData.line) + 1
                width: root.xAt(modelData.end) - root.xAt(modelData.start) - root.charWidth
                height: root.lineHeight - 2
                radius: 4
                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, root.darkColors ? 0.35 : 0.2)
                border { width: 1; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.5) }
            }
        }

        TextEdit {
            id: edit
            x: 6
            y: root.topPad
            width: Math.max(contentWidth, view.width - x)
            readOnly: root.readOnly
            selectByMouse: true
            persistentSelection: true
            activeFocusOnTab: true
            wrapMode: TextEdit.NoWrap
            textFormat: TextEdit.PlainText
            color: "transparent"
            selectedTextColor: "transparent"
            selectionColor: root.editorPalette.selection || Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, root.darkColors ? 0.42 : 0.26)
            font { family: root.fontFamily; pixelSize: root.fontSize }
            tabStopDistance: root.tabWidth * root.charWidth
            cursorDelegate: Rectangle {
                width: 2
                color: root.editorPalette.cursor || (root.darkColors ? "#ffffff" : "#000000")
                visible: edit.activeFocus && !root.readOnly
                SequentialAnimation on opacity {
                    running: edit.activeFocus && !Theme.reduceMotion
                    loops: Animation.Infinite
                    PropertyAction { value: 1 }
                    PauseAnimation { duration: 530 }
                    PropertyAction { value: 0 }
                    PauseAnimation { duration: 530 }
                }
            }
            onTextChanged: root.reparse()
            onCursorRectangleChanged: root.ensureCursorVisible()
            onCursorPositionChanged: if (root.hasPlaceholders) Qt.callLater(() => root.selectPlaceholderAt(edit.cursorPosition))
            Keys.onPressed: (event) => {
                if (root.readOnly) return
                if (root.keyFilter && root.keyFilter(event)) { event.accepted = true; return }
                const typedText = event.key === Qt.Key_Backspace ? "\b" : event.text
                if (typedText && (typedText === "\b" || typedText >= " ") && !(event.modifiers & (Qt.ControlModifier | Qt.MetaModifier)))
                    Qt.callLater(() => root.typed(typedText))
                const mods = event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)
                if (event.key === Qt.Key_Tab && !mods && !edit.selectedText.includes("\n") && root.hasPlaceholders && root.selectPlaceholder(false)) {
                    event.accepted = true
                } else if (event.key === Qt.Key_Backtab && !edit.selectedText.includes("\n") && root.hasPlaceholders && root.selectPlaceholder(true)) {
                    event.accepted = true
                } else if (event.key === Qt.Key_Tab && !mods) {
                    if (edit.selectedText.includes("\n")) root.shiftLines(true)
                    else edit.insert(edit.cursorPosition, root.insertSpaces
                        ? " ".repeat(root.tabWidth - ((root.cursorColumn - 1) % root.tabWidth)) : "\t")
                    event.accepted = true
                } else if (event.key === Qt.Key_Backtab) {
                    root.shiftLines(false)
                    event.accepted = true
                } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !mods && !(event.modifiers & Qt.ShiftModifier)) {
                    root.newline()
                    event.accepted = true
                } else if (event.key === Qt.Key_Backspace && !mods && root.autoClose && root.deletePair()) {
                    event.accepted = true
                } else if (root.autoClose && !mods && root.typePair(event.text)) {
                    event.accepted = true
                } else if ((event.text === "}" || event.text === ")" || event.text === "]") && !mods) {
                    root.closeBrace(event.text)
                    event.accepted = true
                } else if (event.key === Qt.Key_BracketRight && (event.modifiers & Qt.ControlModifier)) {
                    root.shiftLines(true)
                    event.accepted = true
                } else if (event.key === Qt.Key_BracketLeft && (event.modifiers & Qt.ControlModifier)) {
                    root.shiftLines(false)
                    event.accepted = true
                }
            }
        }
    Scroller { flickable: view }

        // The coloured text, one Text per visible line.
        Repeater {
            model: root.visibleCount
            delegate: Text {
                required property int index
                readonly property int line: root.firstVisible + index
                x: edit.x
                y: root.topPad + line * root.lineHeight
                textFormat: Text.StyledText
                font: edit.font
                text: root.revision >= 0 ? root.lineHtml(line) : ""
            }
        }

        // Issue banners after the end of their line, as in Xcode.
        Repeater {
            model: root.issues
            delegate: Rectangle {
                id: banner
                required property var modelData
                required property int index
                readonly property bool first: !root.issues.slice(0, index).some((i) => i.line === modelData.line)
                visible: first
                x: edit.x + (root.revision >= 0 && modelData.line <= root.lines.length
                    ? root.xAt(root.lineStart(modelData.line) + root.lines[modelData.line - 1].length) : 0) + 28
                y: root.lineY(modelData.line) + 1
                height: root.lineHeight - 2
                width: Math.min(560, bannerText.implicitWidth + 30)
                radius: 4
                color: modelData.severity === "error" ? (Theme.dark ? "#66ff453a" : "#33ff3b30") : (Theme.dark ? "#55ffd60a" : "#40ffcc00")
                Symbol {
                    x: 5
                    anchors.verticalCenter: parent.verticalCenter
                    size: Math.min(13, parent.height - 2)
                    name: banner.modelData.severity === "error" ? "xmark-circle" : "warning"
                    tone: banner.modelData.severity === "error" ? "red" : "auto"
                }
                Text {
                    id: bannerText
                    x: 22
                    width: parent.width - 28
                    anchors.verticalCenter: parent.verticalCenter
                    text: banner.modelData.message
                    elide: Text.ElideRight
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: Math.max(10, root.fontSize - 2) }
                }
            }
        }
    }

    // Gutter: line numbers and issue marks.
    Rectangle {
        width: root.gutterWidth
        height: parent.height
        color: root.background
        clip: true
        Repeater {
            model: root.visibleCount
            delegate: Text {
                required property int index
                readonly property int line: root.firstVisible + index + 1
                readonly property bool current: line === root.cursorLine
                x: 0
                width: root.gutterWidth - 12
                y: root.topPad + (line - 1) * root.lineHeight - view.contentY
                height: root.lineHeight
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
                visible: root.showLineNumbers
                text: line
                color: current ? root.editorPalette.plain : (root.editorPalette.lineNumber || (root.darkColors ? "#747478" : "#a6a6a6"))
                font { family: root.fontFamily; pixelSize: root.fontSize - 1; weight: current ? Font.DemiBold : Font.Normal }
            }
        }
        Repeater {
            model: root.issues
            delegate: Symbol {
                required property var modelData
                x: 4
                y: root.lineY(modelData.line) - view.contentY + (root.lineHeight - size) / 2
                size: Math.min(14, root.lineHeight - 2)
                name: modelData.severity === "error" ? "xmark-circle" : "warning"
                tone: modelData.severity === "error" ? "red" : "auto"
            }
        }
        // Click a line number to select the line.
        TapHandler {
            onTapped: (point) => {
                const line = Math.floor((point.position.y + view.contentY - root.topPad) / root.lineHeight) + 1
                if (line < 1 || line > root.lines.length) return
                const start = root.lineStart(line)
                edit.select(start, Math.min(edit.length, start + root.lines[line - 1].length + 1))
                edit.forceActiveFocus()
            }
        }
    }

    // Minimap: the shape of the file in miniature, with the visible part marked.
    Item {
        id: minimap
        visible: root.showMinimap
        x: parent.width - width
        width: root.minimapWidth
        height: parent.height
        readonly property real rowHeight: Math.min(2.4, height / Math.max(1, root.lines.length))
        Rectangle {
            width: 1
            height: parent.height
            color: Theme.separator
        }
        Canvas {
            id: miniCanvas
            anchors.fill: parent
            anchors.leftMargin: 8
            renderStrategy: Canvas.Cooperative
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const lines = root.lines
                if (lines.length > 6000) return
                const palette = root.editorPalette
                const rh = minimap.rowHeight, cw = 1.1
                let state = 0
                for (let i = 0; i < lines.length; i++) {
                    const tok = Syntax.tokenize(lines[i], state, root.language)
                    state = tok.state
                    let col = 0
                    for (const [kind, text] of tok.runs) {
                        const expanded = Syntax.expandTabs(text, root.tabWidth)
                        const trimmed = expanded.trim().length
                        if (trimmed) {
                            const lead = expanded.length - Syntax.ltrim(expanded).length
                            ctx.fillStyle = palette[kind] || palette.plain
                            ctx.globalAlpha = 0.55
                            ctx.fillRect((col + lead) * cw, i * rh, Math.min(trimmed * cw, width - (col + lead) * cw), Math.max(1, rh - 0.6))
                        }
                        col += expanded.length
                        if (col * cw > width) break
                    }
                }
            }
            Timer {
                id: repaint
                interval: 220
                onTriggered: miniCanvas.requestPaint()
            }
            Connections {
                target: root
                function onRevisionChanged() { repaint.restart() }
            }
            Connections {
                target: Theme
                function onDarkChanged() { repaint.restart() }
            }
            Connections {
                target: root
                function onEditorPaletteChanged() { repaint.restart() }
            }
        }
        Rectangle {
            x: 2
            width: parent.width - 4
            y: Math.min(parent.height - height, (view.contentY / root.lineHeight) * minimap.rowHeight)
            height: Math.max(12, (view.height / root.lineHeight) * minimap.rowHeight)
            radius: 3
            color: Theme.dark ? "#1affffff" : "#12000000"
        }
        MouseArea {
            anchors.fill: parent
            function scrollTo(y) {
                const line = y / minimap.rowHeight
                view.contentY = Math.max(0, Math.min(line * root.lineHeight - view.height / 2, view.contentHeight - view.height))
            }
            onPressed: (mouse) => scrollTo(mouse.y)
            onPositionChanged: (mouse) => { if (pressed) scrollTo(mouse.y) }
        }
    }

    // Overlay scroll indicator, shown while scrolling.
    Rectangle {
        x: view.x + view.width - 7
        y: view.visibleArea.yPosition * view.height
        width: 5
        height: Math.max(20, view.visibleArea.heightRatio * view.height)
        radius: 2.5
        visible: view.visibleArea.heightRatio < 1
        color: Theme.dark ? "#66ffffff" : "#55000000"
        opacity: view.moving || scrollFade.running ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Timer { id: scrollFade; interval: 700 }
        Connections {
            target: view
            function onContentYChanged() { scrollFade.restart() }
        }
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: (point) => root.contextMenuRequested(point.position.x, point.position.y)
    }
}
