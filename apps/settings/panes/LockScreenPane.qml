// Lock Screen, as in macOS: when the display turns off, when the password is
// asked for, and a message on the lock screen. gg-idle writes hypridle's
// timers from desktop.json's "lockScreen".
import Quickshell
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    headerSymbol: "lock"; headerTint: "#1d1d1f"; headerTitle: "Lock Screen"
    readonly property var lock: sys.prefs.lockScreen ?? {}
    readonly property var offTimes: [[60, "For 1 minute"], [120, "For 2 minutes"], [300, "For 5 minutes"], [600, "For 10 minutes"],
                                     [1200, "For 20 minutes"], [1800, "For 30 minutes"], [3600, "For 1 hour"], [10800, "For 3 hours"], [0, "Never"]]
    readonly property var requireTimes: [[0, "Immediately"], [5, "After 5 seconds"], [60, "After 1 minute"], [300, "After 5 minutes"],
                                         [900, "After 15 minutes"], [3600, "After 1 hour"], [28800, "After 8 hours"], [-1, "Never"]]
    function index(list, value, fallback) {
        const i = list.findIndex((t) => t[0] === value)
        return i >= 0 ? i : list.findIndex((t) => t[0] === fallback)
    }
    function set(k, v) {
        sys.setPref(["lockScreen", k], v)
        // gg-pref writes desktop.json first; then hypridle gets its new timers.
        Quickshell.execDetached(["sh", "-c", "sleep 0.3; gg-idle"])
    }
    property bool editingMessage: false

    Group {
        SetRow {
            title: "Turn display off when inactive"
            PopUpButton {
                width: 170
                menuParent: pane.nav.overlay
                options: pane.offTimes.map((t) => t[1])
                current: pane.index(pane.offTimes, pane.lock.displayOff ?? 600, 600)
                onPicked: (i) => pane.set("displayOff", pane.offTimes[i][0])
            }
        }
        SetRow {
            title: "Dim the display before it turns off"
            Switch { checked: pane.lock.dim ?? true; onToggled: (on) => pane.set("dim", on) }
        }
        SetRow {
            title: "Require password after display turns off"
            subtitle: (pane.lock.requireAfter ?? 0) === -1 ? "Anyone at your computer can use it after the display turns off. Sleep still locks it." : ""
            PopUpButton {
                width: 170
                menuParent: pane.nav.overlay
                options: pane.requireTimes.map((t) => t[1])
                current: pane.index(pane.requireTimes, pane.lock.requireAfter ?? 0, 0)
                onPicked: (i) => pane.set("requireAfter", pane.requireTimes[i][0])
            }
        }
    }
    Group {
        SetRow {
            title: "Show message when locked"
            subtitle: pane.lock.message ? "“" + pane.lock.message + "”" : "A line under the clock, such as who to call if it's found."
            Switch {
                checked: !!pane.lock.message || pane.editingMessage
                onToggled: (on) => {
                    pane.editingMessage = on
                    if (!on) pane.sys.setPref(["lockScreen", "message"], "")
                    else Qt.callLater(() => messageField.input.forceActiveFocus())
                }
            }
        }
        SetRow {
            visible: pane.editingMessage || !!pane.lock.message
            title: "Message"
            TextField {
                id: messageField
                width: 260
                text: pane.lock.message ?? ""
                placeholder: "If found, please call…"
                onAccepted: { pane.sys.setPref(["lockScreen", "message"], text.trim()); pane.editingMessage = false }
            }
            Button {
                text: "Set"
                onClicked: { pane.sys.setPref(["lockScreen", "message"], messageField.text.trim()); pane.editingMessage = false }
            }
        }
    }
    Group {
        SetRow {
            title: "Lock Screen Now"
            subtitle: "Or press Control-Command-Q."
            Button { text: "Lock"; onClicked: Quickshell.execDetached(["qs", "-c", "golden-gate", "ipc", "call", "lock", "lock"]) }
        }
    }
}
