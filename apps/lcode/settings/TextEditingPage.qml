// Settings ▸ Text Editing: the editor's font, what it shows, indentation, and
// the help it gives while you type and save.
import QtQuick
import "../../lib"
import "../../lib/theme"

Page {
    id: page
    property var families: []
    readonly property var sizes: [9, 10, 11, 12, 13, 14, 15, 16, 18, 20, 22, 24, 28]
    readonly property var fontOptions: ["monospace"].concat(families.filter((f) => f !== "monospace"))
    Component.onCompleted: page.backend.call("fonts", {}, (r) => { if (r.ok) page.families = r.families })

    function set(key, value) { app.saveSettings({ [key]: value }) }

    Rectangle {
        width: parent.width
        height: 150
        radius: 10
        color: page.app.editorColors.background
        border { width: 1; color: Theme.separator }
        clip: true
        CodeEditor {
            anchors { fill: parent; margins: 1 }
            readOnly: true
            language: "python"
            text: "def greet(name: str, times: int = 3) -> str:\n    \"\"\"Hello, a few times over.\"\"\"\n    return \" \".join([f\"Hello, {name}!\"] * times)\n\n\nif __name__ == \"__main__\":\n    print(greet(\"Golden Gate\"))\n"
            colors: page.app.editorColors
            fontFamily: page.app.settings.fontFamily || "monospace"
            fontSize: page.app.settings.fontSize || 13
            tabWidth: page.app.settings.tabWidth || 4
            showMinimap: page.app.settings.showMinimap !== false
            showLineNumbers: page.app.settings.showLineNumbers !== false
            highlightCurrentLine: page.app.settings.highlightCurrentLine !== false
        }
    }
    FormRow {
        label: "Font"
        Row {
            spacing: 8
            PopUpButton {
                width: 220
                options: page.fontOptions.map((f) => f === "monospace" ? "System Monospace" : f)
                current: Math.max(0, page.fontOptions.indexOf(page.app.settings.fontFamily || "monospace"))
                menuParent: page.overlay
                onPicked: (i) => page.set("fontFamily", page.fontOptions[i])
            }
            PopUpButton {
                options: page.sizes.map((s) => s + " pt")
                current: Math.max(0, page.sizes.indexOf(page.app.settings.fontSize || 13))
                menuParent: page.overlay
                onPicked: (i) => page.set("fontSize", page.sizes[i])
            }
        }
    }
    FormRow {
        label: "Show"
        labelHeight: 20
        Column {
            spacing: 8
            Checkbox { width: 440; text: "Line numbers"; checked: page.app.settings.showLineNumbers !== false; onToggled: (on) => page.set("showLineNumbers", on) }
            Checkbox { width: 440; text: "Minimap"; checked: page.app.settings.showMinimap !== false; onToggled: (on) => page.set("showMinimap", on) }
            Checkbox { width: 440; text: "Highlight the current line"; checked: page.app.settings.highlightCurrentLine !== false; onToggled: (on) => page.set("highlightCurrentLine", on) }
        }
    }
    FormGap {}
    FormRow {
        label: "Indent Using"
        Segmented {
            width: 180
            options: ["Spaces", "Tabs"]
            current: page.app.settings.insertSpaces === false ? 1 : 0
            onPicked: (i) => page.set("insertSpaces", i === 0)
        }
    }
    FormRow {
        label: "Tab Width"
        detail: "Python, Rust and Swift style guides use 4; Golden Gate's QML uses 4 too."
        PopUpButton {
            options: ["2 spaces", "3 spaces", "4 spaces", "8 spaces"]
            current: Math.max(0, [2, 3, 4, 8].indexOf(page.app.settings.tabWidth || 4))
            menuParent: page.overlay
            onPicked: (i) => page.set("tabWidth", [2, 3, 4, 8][i])
        }
    }
    FormGap {}
    FormRow {
        label: "While Typing"
        labelHeight: 20
        Column {
            spacing: 8
            Checkbox {
                width: 440
                text: "Suggest completions"
                detail: "Keywords, names from your code, and snippets. ⌘Space shows them any time."
                checked: page.app.settings.codeCompletion !== false
                onToggled: (on) => page.set("codeCompletion", on)
            }
            Checkbox {
                width: 440
                text: "Close brackets and quotes"
                checked: page.app.settings.autoClose !== false
                onToggled: (on) => page.set("autoClose", on)
            }
        }
    }
    FormRow {
        label: "When Saving"
        labelHeight: 20
        Column {
            spacing: 8
            Checkbox {
                width: 440
                text: "Remove trailing whitespace"
                checked: page.app.settings.trimWhitespace !== false
                onToggled: (on) => page.set("trimWhitespace", on)
            }
            Checkbox {
                width: 440
                text: "End the file with a newline"
                checked: page.app.settings.ensureNewline !== false
                onToggled: (on) => page.set("ensureNewline", on)
            }
        }
    }
}
