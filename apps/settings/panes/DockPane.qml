// Golden Gate Desktop & Dock: compact macOS-style grouped settings.
// Each control writes its real consumer: Dock's Prefs singleton or the Hyprland
// floating-window engine, via Sys's atomic windows.json + windows.conf writer.
// Magnification is deliberately absent: it previously caused motion stutter.
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

    readonly property var dock: sys.prefs.dock ?? ({})
    readonly property var windows: sys.windows ?? ({})
    readonly property var defaults: [
        "org.goldengate.Files", "org.goldengate.Web", "org.goldengate.Mail",
        "org.goldengate.Messages", "org.goldengate.Maps", "org.goldengate.Photos",
        "org.goldengate.Music", "org.goldengate.Calendar", "org.goldengate.Notes",
        "org.goldengate.Weather", "org.goldengate.Software",
        "org.goldengate.Settings", "org.goldengate.Terminal"
    ]
    readonly property var pinned: Array.isArray(dock.pinned) ? dock.pinned : defaults
    function setDock(key, value) { sys.setPref(["dock", key], value) }
    function setWindow(key, value) { sys.setWindow(key, value) }
    function moveApp(index, offset) {
        const ids = pinned.slice()
        const target = index + offset
        if (target < 0 || target >= ids.length) return
        const value = ids.splice(index, 1)[0]
        ids.splice(target, 0, value)
        setDock("pinned", ids)
    }
    function removeApp(id) { setDock("pinned", pinned.filter((x) => x !== id)) }
    function addApp(id) {
        if (id && !pinned.includes(id)) setDock("pinned", pinned.concat([id]))
    }

    Group {
        title: "Dock"
        SetRow {
            title: "Size"
            subtitle: "Changes the size of icons and the glass shelf."
            Text { text: "Small"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(11) } }
            Slider {
                objectName: "dockSizeSlider"
                width: 155
                value: ((pane.dock.size ?? 54) - 36) / 44
                onMoved: (v) => pane.setDock("size", Math.round(36 + 44 * v))
            }
            Text { text: "Large"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(11) } }
        }
        SetRow {
            title: "Animate opening applications"
            subtitle: "Subtle, low-overhead Dock feedback on launch."
            Switch { checked: pane.dock.animateLaunch ?? true; onToggled: (on) => pane.setDock("animateLaunch", on) }
        }
        SetRow {
            title: "Show indicators for open applications"
            Switch { checked: pane.dock.indicators ?? true; onToggled: (on) => pane.setDock("indicators", on) }
        }
        SetRow {
            title: "Show recent applications"
            subtitle: "After closing an unpinned app, its icon lingers briefly then fades away."
            Switch { checked: pane.dock.showRecents ?? true; onToggled: (on) => pane.setDock("showRecents", on) }
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
            title: "Touch display and rotation"
            subtitle: "Multi-touch support depends on Linux input drivers. Auto-rotation requires a supported motion sensor and will be added separately."
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
            Button { text: "Restore Defaults"; onClicked: pane.setDock("pinned", pane.defaults.slice()) }
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
            subtitle: "You can also drag a running app into the Dock, or use its Dock context menu."
            Button {
                text: "Add…"
                onClicked: pane.nav.open("dockapps")
            }
        }
    }
}
