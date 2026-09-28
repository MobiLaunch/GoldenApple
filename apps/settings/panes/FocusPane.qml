// Focus: Do Not Disturb, which the shell's notifications follow.
import Quickshell
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    headerSymbol: "moon"; headerTint: "#5e5ce6"; headerTitle: "Focus"
    headerText: "Focus lets you silence notifications so you can concentrate. The moon in the menu bar shows when it's on."
    property bool dnd: false
    Group {
        SetRow {
            title: "Do Not Disturb"; symbol: "moon"; symbolTint: "#5e5ce6"
            subtitle: "Notifications are kept in Notification Center without a banner or sound."
            Switch {
                checked: pane.dnd
                onToggled: (on) => { pane.dnd = on; Quickshell.execDetached(["qs", "-c", "golden-gate", "ipc", "call", "notifications", "toggleDnd"]) }
            }
        }
    }
}
