// Desktop & Dock: size and magnification (live in the Dock as you drag),
// indicators and the launch animation.
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
            Text { text: "Small"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 11 } }
            Slider { width: 200; value: ((pane.dock.size ?? 54) - 36) / (80 - 36); onMoved: (v) => pane.set("size", Math.round(36 + v * 44)) }
            Text { text: "Large"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 11 } }
        }
        SetRow {
            title: "Magnification"
            Switch { checked: pane.dock.magnification ?? true; onToggled: (on) => pane.set("magnification", on) }
            Slider {
                width: 160
                opacity: (pane.dock.magnification ?? true) ? 1 : 0.4
                value: ((pane.dock.magnifiedSize ?? 86) - 60) / (128 - 60)
                onMoved: (v) => pane.set("magnifiedSize", Math.round(60 + v * 68))
            }
        }
        SetRow { title: "Animate opening applications"; Switch { checked: pane.dock.animateLaunch ?? true; onToggled: (on) => pane.set("animateLaunch", on) } }
        SetRow { title: "Show indicators for open applications"; Switch { checked: pane.dock.indicators ?? true; onToggled: (on) => pane.set("indicators", on) } }
    }
}
