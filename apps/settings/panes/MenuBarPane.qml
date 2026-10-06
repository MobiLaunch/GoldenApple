// Menu Bar, as in macOS 26: its background, and what the clock shows.
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    readonly property var bar: sys.prefs.menuBar ?? {}
    function set(k, v) { sys.setPref(["menuBar", k], v) }
    Group {
        title: "Menu Bar"
        SetRow {
            title: "Show menu bar background"
            subtitle: "Off, the menu bar is clear over your wallpaper."
            Switch { checked: pane.bar.background ?? true; onToggled: (on) => pane.set("background", on) }
        }
    }
    Group {
        title: "Clock"
        SetRow { title: "Show the day of the week"; Switch { checked: pane.bar.showDay ?? true; onToggled: (on) => pane.set("showDay", on) } }
        SetRow { title: "Show date"; Switch { checked: pane.bar.showDate ?? true; onToggled: (on) => pane.set("showDate", on) } }
        SetRow { title: "Use a 24-hour clock"; Switch { checked: pane.bar.clock24 ?? false; onToggled: (on) => pane.set("clock24", on) } }
        SetRow { title: "Show seconds"; Switch { checked: pane.bar.seconds ?? false; onToggled: (on) => pane.set("seconds", on) } }
    }
}
