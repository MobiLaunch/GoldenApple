// Sound: the alert sound (CitronOS's own, lib/assets/sounds; choosing one
// plays it, as on the Mac) and the chime when power is connected; output and
// input volume and mute, and the output device, through PipeWire (wpctl).
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    property real volume: 0.5
    property bool muted: false
    property real inVolume: 0.5
    property var sinks: []        // {id, name, current}
    function refresh() {
        sys.sh("wpctl get-volume @DEFAULT_AUDIO_SINK@; wpctl get-volume @DEFAULT_AUDIO_SOURCE@", (o) => {
            const l = o.split("\n")
            const m = /([\d.]+)/.exec(l[0] ?? ""); if (m) volume = Math.min(1, parseFloat(m[1]))
            muted = (l[0] ?? "").includes("MUTED")
            const n = /([\d.]+)/.exec(l[1] ?? ""); if (n) inVolume = Math.min(1, parseFloat(n[1]))
        })
        // The Sinks block of `wpctl status`: " │  *   52. Speakers [vol: 0.40]"
        sys.sh("wpctl status | sed -n '/Sinks:/,/Sources:/p'", (o) => {
            sinks = o.split("\n").map((l) => /(\*)?\s+(\d+)\.\s+(.+?)(\s+\[vol:.*)?$/.exec(l.replace(/[│├└─]/g, " "))).filter((m) => m)
                     .map((m) => ({ id: m[2], name: m[3].trim(), current: !!m[1] }))
        })
    }
    Component.onCompleted: refresh()

    readonly property var alerts: ["Crystal", "Ping", "Pebble", "Bubble", "Breeze", "Chord"]
    readonly property string alert: sys.prefs.sound?.alert ?? "Crystal"
    function soundPath(name) { return decodeURIComponent(Qt.resolvedUrl("../../lib/assets/sounds/" + name + ".wav").toString().replace("file://", "")) }
    function play(name) { sys.run(["sh", "-c", "pw-play \"$1\" 2>/dev/null || paplay \"$1\" 2>/dev/null || true", "sh", soundPath(name)]) }

    Group {
        objectName: "alertSounds"
        title: "Alert sound"
        Repeater {
            model: pane.alerts
            delegate: SetRow {
                required property string modelData
                title: modelData
                selectable: true
                Symbol { visible: pane.alert === modelData; name: "checkmark"; tone: "accent"; size: 14 }
                onClicked: { pane.sys.setPref(["sound", "alert"], modelData); pane.play(modelData) }
            }
        }
    }
    Group {
        SetRow {
            title: "Play sound when connecting to power"
            Switch {
                checked: pane.sys.prefs.sound?.charging ?? true
                onToggled: (on) => { pane.sys.setPref(["sound", "charging"], on); if (on) pane.play("Charging") }
            }
        }
    }

    Group {
        title: "Output"
        Repeater {
            model: pane.sinks
            delegate: SetRow {
                required property var modelData
                title: modelData.name
                subtitle: modelData.current ? "In use" : ""
                Symbol { visible: modelData.current; name: "checkmark"; tone: "accent"; size: 14 }
                Button { visible: !modelData.current; text: "Use"; onClicked: pane.sys.run(["wpctl", "set-default", modelData.id], () => pane.refresh()) }
            }
        }
        SetRow { visible: pane.sinks.length === 0; title: "No output devices found" }
    }
    Group {
        SetRow {
            title: "Output volume"
            Symbol { name: "speaker"; size: 13; opacity: 0.6 }
            Slider { width: 220; value: pane.volume; onMoved: (v) => { pane.volume = v; pane.sys.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", v.toFixed(2)]) } }
            Symbol { name: "speaker-wave"; size: 15 }
        }
        SetRow {
            title: "Mute"
            Switch { checked: pane.muted; onToggled: (on) => { pane.muted = on; pane.sys.run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", on ? "1" : "0"]) } }
        }
        SetRow {
            title: "Input volume"
            Symbol { name: "mic"; size: 13; opacity: 0.6 }
            Slider { width: 220; value: pane.inVolume; onMoved: (v) => { pane.inVolume = v; pane.sys.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SOURCE@", v.toFixed(2)]) } }
        }
    }
}
