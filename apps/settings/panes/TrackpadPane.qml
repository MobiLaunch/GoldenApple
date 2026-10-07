// Trackpad & Mouse: tracking speed, natural scrolling and tap to click.
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    readonly property var i: sys.input
    Group {
        SetRow {
            title: "Tracking speed"
            Text { text: "Slow"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(11) } }
            Slider { width: 200; steps: 8; value: ((pane.i.sensitivity ?? 0) + 1) / 2; onMoved: (v) => pane.sys.setInput("sensitivity", v * 2 - 1) }
            Text { text: "Fast"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(11) } }
        }
        SetRow {
            title: "Natural scrolling"
            subtitle: "Content tracks finger movement."
            Switch { checked: pane.i.naturalScroll ?? true; onToggled: (on) => pane.sys.setInput("naturalScroll", on) }
        }
        SetRow {
            title: "Tap to click"
            subtitle: "Tap with one finger."
            Switch { checked: pane.i.tapToClick ?? true; onToggled: (on) => pane.sys.setInput("tapToClick", on) }
        }
    }
}
