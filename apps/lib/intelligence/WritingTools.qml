import Quickshell
import QtQuick
import ".." as Shared
import "../theme"

Item {
    id: sheet
    objectName: "writingTools"
    property var editor: null
    property string originalDocument: ""
    property string originalContext: ""
    property int start: 0
    property int end: 0
    property bool truncated: false
    property string message: ""
    readonly property var modes: ["proofread", "rewrite", "friendly", "professional", "concise", "summary", "keypoints", "table", "custom"]
    visible: false
    anchors.fill: parent
    z: 2000
    function open() {
        if (!editor || editor.readOnly) return
        originalDocument = editor.text
        originalContext = editor.writingContext || ""
        start = editor.selectionStart
        end = editor.selectionEnd
        if (start === end) { start = 0; end = editor.length }
        source.text = editor.getText(start, end)
        result.text = ""
        message = ""
        service.error = ""
        visible = true
        tools.forceActiveFocus()
    }
    function close() { service.cancel(); visible = false; if (editor) editor.forceActiveFocus() }
    function apply() {
        if (!editor || editor.readOnly || editor.text !== originalDocument || (editor.writingContext || "") !== originalContext) {
            message = "The document changed. Copy the result, or close and reopen Writing Tools for the current text."
            return
        }
        editor.select(start, end)
        // TextSelection inserts plain text in one undo step, even in Markdown
        // Notes. Generated HTML is never interpreted or allowed to load images.
        editor.cursorSelection.text = result.text
        close()
    }
    Service {
        id: service
        onCompleted: (action, reply) => {
            if (!reply.ok) return
            result.text = reply.text
            sheet.truncated = reply.truncated
            sheet.message = reply.truncated ? "The response was cut short. Try a shorter selection before replacing text." : "Review the result before replacing your text."
        }
    }
    Shortcut { sequence: "Escape"; enabled: sheet.visible; onActivated: sheet.close() }
    Rectangle { anchors.fill: parent; color: "#66000000"; MouseArea { anchors.fill: parent } }
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(740, parent.width - 32)
        height: Math.min(640, parent.height - 32)
        radius: 22; color: Theme.contentBg
        border { width: 1; color: Theme.separator }
        Flickable {
            anchors { fill: parent; margins: 22 }
            contentWidth: width; contentHeight: controls.height
            clip: true; boundsBehavior: Flickable.StopAtBounds
        Column {
            id: controls
            width: parent.width; spacing: 12
            Row {
                spacing: 9
                Shared.Symbol { name: "wand"; tone: "accent"; size: 24 }
                Text { text: "Writing Tools"; color: Theme.label; font { family: Theme.fontUi; pixelSize: Theme.fs(22); weight: Font.Bold } }
            }
            Text { text: "Citron Intelligence · Google Gemini"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(12) } }
            EditorBox { id: source; width: parent.width; height: Math.max(65, (card.height - 374) * 0.42); readOnly: true }
            Shared.PopUpButton {
                id: tools; width: 200; menuParent: sheet
                enabled: !service.busy
                options: ["Proofread", "Rewrite", "Friendly", "Professional", "Concise", "Summary", "Key Points", "Table", "Describe Your Change"]
            }
            Shared.TextField {
                id: instruction; width: parent.width; height: 32
                visible: tools.current === 8
                placeholder: "For example: translate into Spanish"
                enabled: !service.busy
            }
            Row {
                spacing: 8
                Shared.Button {
                    text: service.busy ? "Working…" : "Send to Gemini"; prominent: true
                    enabled: !service.busy && source.text.trim().length > 0 && (tools.current !== 8 || instruction.text.trim().length > 0)
                    onClicked: {
                        result.text = ""; sheet.message = ""; sheet.truncated = false
                        service.send({ task: "writing", mode: sheet.modes[tools.current], text: source.text, prompt: instruction.text })
                    }
                }
                Shared.Button { text: "Cancel Request"; visible: service.busy; onClicked: service.cancel() }
            }
            EditorBox { id: result; objectName: "writingResult"; width: parent.width; height: Math.max(70, (card.height - 374) * 0.58 - (instruction.visible ? 44 : 0)); readOnly: true; placeholder: "Your result appears here" }
            Text {
                width: parent.width; height: 34; wrapMode: Text.Wrap; elide: Text.ElideRight
                text: service.error || sheet.message || "Only the text shown above is sent to Google when you choose Send."
                color: service.error ? "#ff453a" : Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
            }
            Row {
                spacing: 8
                Shared.Button { text: "Close"; onClicked: sheet.close() }
                Shared.Button { text: "Copy"; enabled: !!result.text; onClicked: Quickshell.clipboardText = result.text }
                Shared.Button { text: "Replace"; prominent: true; enabled: !!result.text && !service.busy && !sheet.truncated; onClicked: sheet.apply() }
            }
        }
        }
    }
}
