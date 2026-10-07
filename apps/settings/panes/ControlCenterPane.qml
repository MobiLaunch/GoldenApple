// Control Center, as in macOS: which items the menu bar shows. The shell's
// menu bar follows desktop.json's menuBar.items at once.
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    headerSymbol: "control-center"; headerTint: "#8e8e93"; headerTitle: "Control Center"
    headerText: "Choose what the menu bar shows. Everything is always in Control Center."
    readonly property var items: sys.prefs.menuBar?.items ?? {}
    function shows(k, def) { return items[k] ?? def }
    function set(k, v) { sys.setPref(["menuBar", "items", k], v) }

    Group {
        title: "Control Center Modules"
        SetRow { title: "Wi-Fi"; symbol: "wifi"; symbolTint: "#0a84ff"
            Switch { checked: pane.shows("wifi", true); onToggled: (on) => pane.set("wifi", on) } }
        SetRow { title: "Bluetooth"; symbol: "bluetooth"; symbolTint: "#0a84ff"
            Switch { checked: pane.shows("bluetooth", false); onToggled: (on) => pane.set("bluetooth", on) } }
        SetRow { title: "Sound"; symbol: "speaker-wave"; symbolTint: "#ff2d55"
            Switch { checked: pane.shows("sound", false); onToggled: (on) => pane.set("sound", on) } }
        SetRow { title: "Focus"; subtitle: "Shown while Do Not Disturb is on."; symbol: "moon"; symbolTint: "#5e5ce6"
            Switch { checked: pane.shows("focus", true); onToggled: (on) => pane.set("focus", on) } }
        SetRow { title: "Now Playing"; subtitle: "The song or video that's playing."; symbol: "music"; symbolTint: "#ff2d55"
            Switch { checked: pane.shows("nowPlaying", false); onToggled: (on) => pane.set("nowPlaying", on) } }
    }
    Group {
        title: "Other Modules"
        SetRow { title: "Battery"; symbol: "power"; symbolTint: "#34c759"
            Switch { checked: pane.shows("battery", true); onToggled: (on) => pane.set("battery", on) } }
        SetRow { title: "Show Percentage"; subtitle: "Next to the battery in the menu bar."
            Switch { enabled: pane.shows("battery", true); checked: pane.shows("batteryPercent", false); onToggled: (on) => pane.set("batteryPercent", on) } }
    }
    Group {
        title: "Menu Bar Only"
        SetRow { title: "Spotlight"; symbol: "search"; symbolTint: "#8e8e93"
            Switch { checked: pane.shows("spotlight", true); onToggled: (on) => pane.set("spotlight", on) } }
        SetRow { title: "Citron Intelligence"; symbol: "wand"; symbolTint: "#9564e8"
            Switch { checked: pane.shows("citron", true); onToggled: (on) => pane.set("citron", on) } }
    }
}
