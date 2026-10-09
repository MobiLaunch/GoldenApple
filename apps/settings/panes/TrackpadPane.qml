// macOS-inspired trackpad and mouse controls, all persisted by set-prefs.py.
// Uses Hyprland's native input.touchpad options and applies live via hyprctl.
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    headerSymbol: "rectangle-fill"
    headerTint: "#8e8e93"
    headerTitle: "Trackpad & Mouse"
    headerText: "Adjust pointer speed, scrolling, taps, clicks and dragging."
    readonly property var i: sys.input ?? ({})
    Group {
        title: "Point & Click"
        SetRow {
            title: "Tracking speed"
            subtitle: "How quickly the pointer moves as you move your finger or mouse."
            Text { text: "Slow"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(11) } }
            Slider {
                objectName: "pointerSpeed"
                width: 160; steps: 8
                value: ((pane.i.sensitivity ?? 0) + 1) / 2
                onMoved: (v) => pane.sys.setInput("sensitivity", Math.round((v * 2 - 1) * 100) / 100)
            }
            Text { text: "Fast"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(11) } }
        }
        SetRow {
            title: "Tap to click"
            subtitle: "Tap one finger instead of pressing down."
            Switch { checked: pane.i.tapToClick ?? true; onToggled: (on) => pane.sys.setInput("tapToClick", on) }
        }
        SetRow {
            title: "Secondary click"
            subtitle: "Press with two fingers to show a context menu."
            Switch { checked: pane.i.twoFingerClick ?? true; onToggled: (on) => pane.sys.setInput("twoFingerClick", on) }
        }
        SetRow {
            title: "Disable trackpad while typing"
            subtitle: "Avoid accidental cursor movement while pressing keys."
            Switch { checked: pane.i.disableWhileTyping ?? true; onToggled: (on) => pane.sys.setInput("disableWhileTyping", on) }
        }
    }
    Group {
        title: "Scroll & Zoom"
        SetRow {
            title: "Natural scrolling"
            subtitle: "Content moves in the same direction as your fingers."
            Switch { checked: pane.i.naturalScroll ?? true; onToggled: (on) => pane.sys.setInput("naturalScroll", on) }
        }
        SetRow {
            title: "Scroll speed"
            subtitle: "Adjust the distance scrolled per gesture."
            Text { text: "Slow"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(11) } }
            Slider {
                objectName: "trackpadScrollFactor"
                width: 164; steps: 10
                value: ((pane.i.scrollFactor ?? 0.6) - 0.3) / 2.7
                onMoved: (v) => pane.sys.setInput("scrollFactor", Math.round((0.3 + 2.7 * v) * 100) / 100)
            }
            Text { text: "Fast"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(11) } }
        }
    }
    Group {
        title: "Dragging"
        SetRow {
            title: "Tap and drag"
            subtitle: "Tap twice and keep your finger down on the second tap to drag."
            Switch { checked: pane.i.tapAndDrag ?? true; onToggled: (on) => pane.sys.setInput("tapAndDrag", on) }
        }
        SetRow {
            title: "Drag lock"
            subtitle: "Continue dragging briefly after lifting your finger."
            PopUpButton {
                menuParent: pane.nav.overlay
                options: ["Off", "With Timeout", "Sticky"]
                current: Math.max(0, Math.min(2, pane.i.dragLock ?? 0))
                enabled: pane.i.tapAndDrag ?? true
                onPicked: (index) => pane.sys.setInput("dragLock", index)
            }
        }
    }
}
