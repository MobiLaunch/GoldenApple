// Spotlight, as in macOS: which kinds of result it shows. The shell's
// Spotlight follows desktop.json's "spotlight" at once.
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    headerSymbol: "search"; headerTint: "#8e8e93"; headerTitle: "Spotlight"
    headerText: "Spotlight finds apps, settings, documents and answers as you type. Press Command-Space to search."
    readonly property var shown: sys.prefs.spotlight ?? {}
    readonly property var kinds: [
        ["apps", "Applications", "apps", "#0a84ff"],
        ["answers", "Calculator and Conversions", "calculator", "#8e8e93"],
        ["settings", "System Settings", "gear", "#8e8e93"],
        ["files", "Documents and Folders", "doc", "#0a84ff"],
        ["web", "Search the Web", "globe", "#30b0c7"]
    ]
    Group {
        title: "Search Results"
        Repeater {
            model: pane.kinds
            delegate: SetRow {
                id: kindRow
                required property var modelData
                title: modelData[1]; symbol: modelData[2]; symbolTint: modelData[3]
                Switch {
                    checked: pane.shown[kindRow.modelData[0]] ?? true
                    onToggled: (on) => pane.sys.setPref(["spotlight", kindRow.modelData[0]], on)
                }
            }
        }
    }
}
