// Keyboard: key repeat and the input source (layout), applied to Hyprland at
// once and kept in input.conf.
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."
import "../../setup/regions.js" as Regions

Pane {
    id: pane
    readonly property var i: sys.input
    readonly property var layouts: [...new Set(Regions.LIST.map((r) => r.keyboard))].sort()
    Group {
        SetRow {
            title: "Key repeat rate"
            Text { text: "Slow"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 11 } }
            Slider { width: 180; steps: 7; value: ((pane.i.repeatRate ?? 25) - 5) / 45; onMoved: (v) => pane.sys.setInput("repeatRate", 5 + v * 45) }
            Text { text: "Fast"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 11 } }
        }
        SetRow {
            title: "Delay until repeat"
            Text { text: "Long"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 11 } }
            Slider { width: 180; steps: 5; value: 1 - ((pane.i.repeatDelay ?? 600) - 150) / 850; onMoved: (v) => pane.sys.setInput("repeatDelay", 150 + (1 - v) * 850) }
            Text { text: "Short"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 11 } }
        }
    }
    Group {
        title: "Text Input"
        SetRow {
            title: "Input source"
            PopUpButton {
                menuParent: pane.nav.overlay
                options: pane.layouts.map((k) => k.toUpperCase())
                current: Math.max(0, pane.layouts.indexOf((pane.i.layout ?? "us") + (pane.i.variant ? "(" + pane.i.variant + ")" : "")))
                onPicked: (idx) => { const l = Regions.layout(pane.layouts[idx]); pane.sys.setInput("variant", l.variant); pane.sys.setInput("layout", l.layout) }
            }
        }
    }
}
