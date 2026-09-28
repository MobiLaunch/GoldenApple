// Sound: output and input volume and mute, and the output device, through
// PipeWire (wpctl).
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
