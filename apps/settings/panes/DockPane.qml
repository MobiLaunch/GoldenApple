// Desktop & Dock: fixed iPad-style shelf sizing, running indicators and the
// launch animation. Magnification was intentionally removed for stable geometry.
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    readonly property var dock: sys.prefs.dock ?? {}
    function set(k, v) { sys.setPref(["dock", k], v) }
    Group {
        title: "Dock"
        SetRow {
            title: "Size"
            Text { text: "Small"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(11) } }
            Slider { width: 200; value: ((pane.dock.size ?? 54) - 36) / (80 - 36); onMoved: (v) => pane.set("size", Math.round(36 + v * 44)) }
            Text { text: "Large"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(11) } }
        }
        SetRow { title: "Animate opening applications"; Switch { checked: pane.dock.animateLaunch ?? true; onToggled: (on) => pane.set("animateLaunch", on) } }
        SetRow { title: "Show indicators for open applications"; Switch { checked: pane.dock.indicators ?? true; onToggled: (on) => pane.set("indicators", on) } }
    }
}
