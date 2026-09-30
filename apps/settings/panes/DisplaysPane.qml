// Displays: each screen with its resolution and scale (Hyprland), brightness
// (brightnessctl) and Night Shift (hyprsunset).
import Quickshell
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    property var monitors: []
    property real brightness: -1
    property bool nightShift: false
    property int warmth: 4500
    function refresh() {
        sys.run(["hyprctl", "monitors", "-j"], (o) => { try { monitors = JSON.parse(o) } catch (e) { monitors = [] } })
        sys.sh("brightnessctl -m 2>/dev/null | cut -d, -f4", (o) => brightness = o.trim() ? parseInt(o) / 100 : -1)
        sys.sh("pgrep -x hyprsunset >/dev/null && echo on", (o) => nightShift = o.trim() === "on")
    }
    Component.onCompleted: {
        warmth = sys.prefs.display?.warmth ?? 4500
        refresh()
    }
    // Scales Hyprland renders well at: fractions of 120.
    readonly property var scales: [1, 1.25, 1.5, 1.6, 2]
    function setScale(m, s) {
        const conf = m.name + ", " + m.width + "x" + m.height + "@" + Math.round(m.refreshRate) + ", auto, " + s
        sys.run(["hyprctl", "keyword", "monitor", conf], () => refresh())
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1"; f="$1/displays.conf"; touch "$f"; grep -v "^monitor = $2," "$f" > "$f.tmp"; echo "monitor = $3" >> "$f.tmp"; mv "$f.tmp" "$f"',
                                 "sh", sys.config + "/hypr/golden-gate", m.name, conf])
    }

    Repeater {
        model: pane.monitors
        delegate: Group {
            required property var modelData
            title: modelData.description || modelData.name
            SetRow { title: "Resolution"; Text { text: modelData.width + " × " + modelData.height + " at " + Math.round(modelData.refreshRate) + " Hz"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 13 } } }
            SetRow {
                title: "Scale"
                subtitle: "Looks like " + Math.round(modelData.width / modelData.scale) + " × " + Math.round(modelData.height / modelData.scale)
                Segmented {
                    options: pane.scales.map((s) => Math.round(s * 100) + "%")
                    current: Math.max(0, pane.scales.findIndex((s) => Math.abs(s - modelData.scale) < 0.01))
                    onPicked: (i) => pane.setScale(modelData, pane.scales[i])
                }
            }
        }
    }
    Group {
        visible: pane.brightness >= 0
        SetRow {
            title: "Brightness"
            Symbol { name: "sun"; size: 13; opacity: 0.6 }
            Slider {
                width: 220
                value: pane.brightness
                onMoved: (v) => {
                    pane.brightness = v
                    pane.sys.setPref(["display", "brightness"], v)
                    pane.sys.run(["brightnessctl", "set", Math.round(Math.max(0.02, v) * 100) + "%"])
                }
            }
            Symbol { name: "sun-max"; size: 16 }
        }
    }
    Group {
        title: "Night Shift"
        SetRow {
            title: "Night Shift"
            subtitle: "Shifts the colours of the display to the warmer end of the spectrum."
            Switch {
                checked: pane.nightShift
                onToggled: (on) => {
                    pane.nightShift = on
                    pane.sys.setPref(["display", "nightShift"], on)
                    if (on) Quickshell.execDetached(["hyprsunset", "-t", String(pane.warmth)])
                    else pane.sys.run(["pkill", "-x", "hyprsunset"])
                }
            }
        }
        SetRow {
            title: "Colour temperature"
            Text { text: "Less Warm"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 11 } }
            Slider {
                width: 180
                value: (6000 - pane.warmth) / 3000
                onMoved: (v) => {
                    pane.warmth = Math.round(6000 - v * 3000)
                    pane.sys.setPref(["display", "warmth"], pane.warmth)
                    if (pane.nightShift) { pane.sys.sh("pkill -x hyprsunset; sleep 0.2; setsid -f hyprsunset -t " + pane.warmth + " >/dev/null 2>&1") }
                }
            }
            Text { text: "More Warm"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 11 } }
        }
    }
}
