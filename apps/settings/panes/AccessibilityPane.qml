// Accessibility: Reduce motion (Hyprland's animations and GTK's), larger text,
// and Reduce transparency for the shell's glass.
import Quickshell
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    headerSymbol: "person"; headerTint: "#0a84ff"; headerTitle: "Accessibility"
    headerText: "Personalize this computer to make it easier to see, hear and use."
    property real textScale: 1
    Component.onCompleted: sys.run(["gsettings", "get", "org.gnome.desktop.interface", "text-scaling-factor"], (o) => textScale = parseFloat(o) || 1)
    readonly property bool reduceMotion: sys.prefs.reduceMotion ?? false

    Group {
        title: "Display"
        SetRow {
            title: "Reduce motion"
            subtitle: "Windows and menus fade instead of springing; the Dock doesn't magnify."
            Switch {
                checked: pane.reduceMotion
                onToggled: (on) => {
                    pane.sys.setPref(["reduceMotion"], on)
                    pane.sys.run(["hyprctl", "keyword", "animations:enabled", on ? "0" : "1"])
                    pane.sys.run(["gsettings", "set", "org.gnome.desktop.interface", "enable-animations", on ? "false" : "true"])
                    Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && printf "animations {\\n    enabled = %s\\n}\\n" "$2" > "$1/accessibility.conf"', "sh", pane.sys.config + "/hypr/golden-gate", on ? "false" : "true"])
                }
            }
        }
        SetRow {
            title: "Reduce transparency"
            subtitle: "Glass is more opaque, for more contrast."
            Switch { checked: pane.sys.prefs.reduceTransparency ?? false; onToggled: (on) => pane.sys.setPref(["reduceTransparency"], on) }
        }
        SetRow {
            title: "Text size"
            subtitle: Math.round(pane.textScale * 100) + "%"
            Slider {
                width: 200; steps: 5
                value: (pane.textScale - 1) / 0.5
                // CitronOS's own apps and shell (Theme.textScale, from desktop.json)
                // and GTK apps (GNOME's text-scaling-factor) both follow it.
                onMoved: (v) => {
                    pane.textScale = 1 + v * 0.5
                    pane.sys.setPref(["textScale"], Math.round(pane.textScale * 100) / 100)
                    pane.sys.run(["gsettings", "set", "org.gnome.desktop.interface", "text-scaling-factor", pane.textScale.toFixed(2)])
                }
            }
        }
    }
}
