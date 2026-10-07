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
    // Scales Hyprland renders well at: fractions of 120. A scale is offered
    // for a display only when its resolution divides into whole pixels.
    readonly property var scales: [1, 1.25, 1.5, 1.6, 2]
    function fits(m, s) {
        const w = m.width / s, h = m.height / s
        return Math.abs(w - Math.round(w)) < 0.01 && Math.abs(h - Math.round(h)) < 0.01
    }
    // The rule for a display as it is, or with a new scale / position: its
    // exact mode (the refresh rate as Hyprland reports it) and its place.
    function rule(m, scale, x, y) {
        return m.name + ", " + m.width + "x" + m.height + "@" + Number(m.refreshRate).toFixed(3) + ", "
            + Math.round(x ?? m.x) + "x" + Math.round(y ?? m.y) + ", " + (scale ?? m.scale)
    }
    // Rules that change m's scale and keep the arrangement: displays to its
    // right or below move by however much m grew or shrank.
    function scaledRules(m, s) {
        const oldW = m.width / m.scale, oldH = m.height / m.scale
        const dw = m.width / s - oldW, dh = m.height / s - oldH
        const out = [rule(m, s)]
        for (const o of monitors) {
            if (o.name === m.name) continue
            const right = o.x >= m.x + oldW - 1, below = o.y >= m.y + oldH - 1
            if (right || below) out.push(rule(o, o.scale, o.x + (right ? dw : 0), o.y + (below ? dh : 0)))
        }
        return out
    }

    // A change is tried live, then kept only when you say so: without an
    // answer in 15 seconds it goes back (a display you can't read can't be
    // confirmed). Only kept changes are written to displays.conf.
    property var previous: []           // the rules to go back to
    property var pending: []            // the rules being tried
    property int countdown: 0
    property string scaleError: ""
    function apply(rules, done) {
        sys.run(["hyprctl", "--batch", rules.map((r) => "keyword monitor " + r).join(" ; ")], (out, code) => done(code === 0 && !/error|invalid/i.test(out)))
    }
    function setScale(m, s) {
        if (pending.length || !fits(m, s)) return
        scaleError = ""
        const before = monitors.map((o) => rule(o))
        const tryRules = scaledRules(m, s)
        apply(tryRules, (ok) => {
            sys.run(["hyprctl", "monitors", "-j"], (o) => {
                let now = []
                try { now = JSON.parse(o) } catch (e) {}
                const got = now.find((x) => x.name === m.name)
                if (!ok || !got || Math.abs(got.scale - s) > 0.01) {
                    apply(before, () => refresh())
                    scaleError = "That scale couldn't be used on " + (m.description || m.name) + "; the display was left as it was."
                    return
                }
                monitors = now
                previous = before
                pending = tryRules
                countdown = 15
                revertTimer.restart()
            })
        })
    }
    function keep() {
        revertTimer.stop()
        const rules = pending
        pending = []
        previous = []
        // displays.conf: this computer's rules, one per display, the others kept.
        const f = sys.config + "/hypr/golden-gate/displays.conf"
        sys.run(["cat", f], (text) => {
            const names = rules.map((r) => r.split(",")[0])
            const kept = text.split("\n").filter((l) => l.trim() && !names.some((n) => l.startsWith("monitor = " + n + ",")))
            sys.writeFile(f, kept.concat(rules.map((r) => "monitor = " + r)).join("\n") + "\n", "displays.conf")
        })
    }
    function revert() {
        revertTimer.stop()
        const rules = previous
        pending = []
        previous = []
        if (rules.length) apply(rules, () => refresh())
    }
    Timer {
        id: revertTimer
        interval: 1000
        repeat: true
        onTriggered: { if (--pane.countdown <= 0) pane.revert() }
    }

    Group {
        objectName: "displaysKeep"
        visible: pane.pending.length > 0
        SetRow {
            title: "Keep these display settings?"
            subtitle: "Going back to the previous settings in " + pane.countdown + (pane.countdown === 1 ? " second." : " seconds.")
            Button { text: "Revert"; onClicked: pane.revert() }
            Button { text: "Keep Changes"; prominent: true; onClicked: pane.keep() }
        }
    }
    Text {
        visible: !!pane.scaleError
        width: parent ? parent.width : 400
        wrapMode: Text.WordWrap
        text: pane.scaleError
        color: "#ff453a"
        font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
    }

    Repeater {
        model: pane.monitors
        delegate: Group {
            required property var modelData
            title: modelData.description || modelData.name
            SetRow { title: "Resolution"; Text { text: modelData.width + " × " + modelData.height + " at " + Math.round(modelData.refreshRate) + " Hz"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(13) } } }
            SetRow {
                title: "Scale"
                subtitle: "Looks like " + Math.round(modelData.width / modelData.scale) + " × " + Math.round(modelData.height / modelData.scale)
                Segmented {
                    readonly property var offered: pane.scales.filter((s) => pane.fits(modelData, s) || Math.abs(s - modelData.scale) < 0.01)
                    enabled: !pane.pending.length
                    options: offered.map((s) => Math.round(s * 100) + "%")
                    current: Math.max(0, offered.findIndex((s) => Math.abs(s - modelData.scale) < 0.01))
                    onPicked: (i) => pane.setScale(modelData, offered[i])
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
            subtitle: "Shifts the colors of the display to the warmer end of the spectrum."
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
            title: "Color temperature"
            Text { text: "Less Warm"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(11) } }
            Slider {
                width: 180
                value: (6000 - pane.warmth) / 3000
                onMoved: (v) => {
                    pane.warmth = Math.round(6000 - v * 3000)
                    pane.sys.setPref(["display", "warmth"], pane.warmth)
                    if (pane.nightShift) { pane.sys.sh("pkill -x hyprsunset; sleep 0.2; setsid -f hyprsunset -t " + pane.warmth + " >/dev/null 2>&1") }
                }
            }
            Text { text: "More Warm"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: Theme.fs(11) } }
        }
    }
}
