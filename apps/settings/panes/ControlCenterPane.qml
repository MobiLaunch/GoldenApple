// Control Center, as in macOS: what the menu bar and Control Center show. The
// menu bar is MacShell's; its items are chosen in its own settings window
// (Desktop & Dock Settings › Menu Bar), which this pane opens.
import Quickshell
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    headerSymbol: "control-center"; headerTint: "#8e8e93"; headerTitle: "Control Center"
    headerText: "Choose what the menu bar shows. Everything is always in Control Center."

    Group {
        title: "Menu Bar"
        SetRow {
            title: "Menu bar items"
            subtitle: "Wi-Fi, Bluetooth, sound, battery, the clock and the rest are chosen in the menu bar's settings."
            symbol: "control-center"; symbolTint: "#8e8e93"
            Button {
                objectName: "openMenuBarSettings"
                text: "Menu Bar Settings…"
                onClicked: Quickshell.execDetached(["qs", "-c", "golden-gate", "ipc", "call", "settings", "pane", "menubar"])
            }
        }
        SetRow {
            title: "Open Control Center"
            subtitle: "Or click its icon in the menu bar, or press Option-Command-C."
            Button { text: "Open"; onClicked: Quickshell.execDetached(["qs", "-c", "golden-gate", "ipc", "call", "controlcenter", "toggle"]) }
        }
    }
}
