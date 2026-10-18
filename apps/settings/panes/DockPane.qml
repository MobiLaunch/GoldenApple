// Desktop & Dock: the Dock's apps (MacShell's Dock, through Sys's dockPins),
// Tablet Mode, and how windows move, resize and snap (the Hyprland
// floating-window engine, via Sys's atomic windows.json + windows.lua writer).
// The Dock's look and behaviour are set in MacShell's own Desktop & Dock
// Settings window, which this pane opens.
import Quickshell
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    headerSymbol: "apps"
    headerTint: "#487bd9"
    headerTitle: "Desktop & Dock"
    headerText: "Customize the Dock, arrange apps, and adjust how windows move, resize and snap."

    readonly property var windows: sys.windows ?? ({})
    readonly property var pinned: sys.dockPins
    function setWindow(key, value) { sys.setWindow(key, value) }
    function moveApp(index, offset) {
        const ids = pinned.slice()
        const target = index + offset
        if (target < 0 || target >= ids.length) return
        const value = ids.splice(index, 1)[0]
        ids.splice(target, 0, value)
        sys.setDockPins(ids)
    }
    function removeApp(id) { sys.setDockPins(pinned.filter((x) => x !== id)) }
    function addApp(id) {
        if (id && !pinned.includes(id)) sys.setDockPins(pinned.concat([id]))
    }

    Group {
        title: "Dock"
        SetRow {
            title: "Size, magnification, position and more"
            subtitle: "The Dock, the menu bar and the desktop widgets have their own settings window."
            Button {
                objectName: "openDockSettings"
                text: "Dock Settings…"
                onClicked: Quickshell.execDetached(["qs", "-c", "golden-gate", "ipc", "call", "settings", "pane", "dock"])
            }
        }
    }
    Group {
        title: "Tablet Mode"
        SetRow {
            title: "Touch-first desktop"
            subtitle: "iPad-inspired Home Screen layout, larger Dock icons and comfortable touch targets. Your desktop apps and files remain unchanged."
            Switch {
                objectName: "tabletModeToggle"
                checked: pane.sys.prefs.tablet?.enabled ?? false
                onToggled: (on) => pane.sys.setPref(["tablet", "enabled"], on)
            }
        }
        SetRow {
            title: "Home Screen widgets"
            subtitle: "Add, resize, remove and rearrange touch widgets without changing the desktop layout."
            Button {
                text: "Customize Home…"
                enabled: pane.sys.prefs.tablet?.enabled ?? false
                onClicked: pane.sys.run(["qs", "-c", "golden-gate", "ipc", "call", "tablet", "edit"], () => {})
            }
        }
        SetRow {
            title: "Touch display and rotation"
            subtitle: "Compatible touchscreens use Wayland touch input. Open the on-screen keyboard when no physical keyboard is attached."
            Button { text: "Show Keyboard"; onClicked: pane.sys.run(["gg-tablet-keyboard", "show"], () => {}) }
            Button { text: "Hide"; onClicked: pane.sys.run(["gg-tablet-keyboard", "hide"], () => {}) }
        }
    }
    Group {
        title: "Windows"
        SetRow {
            title: "Snap windows"
            subtitle: "Attract floating windows to one another and monitor edges while dragging."
            Switch { checked: pane.windows.snapEnabled ?? true; onToggled: (on) => pane.setWindow("snapEnabled", on) }
        }
        SetRow {
            title: "Snap distance"
            subtitle: "The distance at which window edges attract one another."
            Text { text: "Near"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(11) } }
            Slider {
                width: 134
                enabled: pane.windows.snapEnabled ?? true
                steps: 8
                value: ((pane.windows.windowGap ?? 12) - 4) / 32
                onMoved: (v) => pane.setWindow("windowGap", Math.round(4 + 32 * v))
            }
            Text { text: (pane.windows.windowGap ?? 12) + " px"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(11) } }
        }
        SetRow {
            title: "Screen edge attraction"
            subtitle: "How close a window must come to the edge of the display."
            Text { text: "Near"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(11) } }
            Slider {
                width: 134
                enabled: pane.windows.snapEnabled ?? true
                steps: 8
                value: ((pane.windows.monitorGap ?? 12) - 4) / 32
                onMoved: (v) => pane.setWindow("monitorGap", Math.round(4 + 32 * v))
            }
            Text { text: (pane.windows.monitorGap ?? 12) + " px"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(11) } }
        }
        SetRow {
            title: "Keep spacing between snapped windows"
            Switch {
                enabled: pane.windows.snapEnabled ?? true
                checked: pane.windows.respectGaps ?? true
                onToggled: (on) => pane.setWindow("respectGaps", on)
            }
        }
        SetRow {
            title: "Resize windows from their edges"
            subtitle: "Drag the frame near a corner or edge to resize."
            Switch { checked: pane.windows.resizeOnBorder ?? true; onToggled: (on) => pane.setWindow("resizeOnBorder", on) }
        }
        SetRow {
            title: "Resize handle size"
            subtitle: "Invisible grab area around the window border."
            Text { text: "Small"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(11) } }
            Slider {
                width: 128
                enabled: pane.windows.resizeOnBorder ?? true
                steps: 6
                value: ((pane.windows.grabArea ?? 12) - 4) / 24
                onMoved: (v) => pane.setWindow("grabArea", Math.round(4 + v * 24))
            }
            Text { text: (pane.windows.grabArea ?? 12) + " px"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(11) } }
        }
    }
    Group {
        title: "Applications in the Dock"
        SetRow {
            title: "Pinned applications"
            subtitle: "Move an app up or down to change its position in the Dock."
            Button { text: "Restore Defaults"; onClicked: pane.sys.setDockPins(pane.sys.defaultDockPins.slice()) }
        }
        Repeater {
            model: pane.pinned
            delegate: SetRow {
                id: appRow
                required property string modelData
                readonly property int pinIndex: pane.pinned.indexOf(modelData)
                title: modelData.split(".").pop().replace(/([a-z])([A-Z])/g, "$1 $2")
                image: Quickshell.iconPath(modelData, true)
                Button { text: "↑"; enabled: appRow.pinIndex > 0; onClicked: pane.moveApp(appRow.pinIndex, -1) }
                Button { text: "↓"; enabled: appRow.pinIndex < pane.pinned.length - 1; onClicked: pane.moveApp(appRow.pinIndex, 1) }
                Button { text: "Remove"; onClicked: pane.removeApp(appRow.modelData) }
            }
        }
        SetRow {
            title: "Add an app"
            subtitle: "You can also use an app's Dock menu (Keep in Dock), or Add to Dock in Launchpad."
            Button {
                text: "Add…"
                onClicked: pane.nav.open("dockapps")
            }
        }
    }
}
