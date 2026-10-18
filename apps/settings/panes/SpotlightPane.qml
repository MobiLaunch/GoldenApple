// Spotlight, as in macOS. Spotlight is MacShell's: it finds apps and files,
// and keeps the clipboard history and the emoji picker. This pane says how to
// reach each; it has nothing to set.
import Quickshell
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    headerSymbol: "search"; headerTint: "#8e8e93"; headerTitle: "Spotlight"
    headerText: "Spotlight finds apps and files as you type. Press Command-Space to search."
    readonly property var ways: [
        ["Search", "Command-Space", "search", "#8e8e93", "toggle"],
        ["Clipboard History", "Shift-Command-V", "paste", "#0a84ff", "clipboard"],
        ["Emoji & Symbols", "Control-Command-Space", "smile", "#ff9f0a", "emoji"]
    ]
    Group {
        title: "Spotlight"
        Repeater {
            model: pane.ways
            delegate: SetRow {
                id: wayRow
                required property var modelData
                title: modelData[0]; subtitle: modelData[1]; symbol: modelData[2]; symbolTint: modelData[3]
                Button { text: "Open"; onClicked: Quickshell.execDetached(["qs", "-c", "golden-gate", "ipc", "call", "spotlight", wayRow.modelData[4]]) }
            }
        }
    }
}
