// General › AirPlay Receiver: an iPhone, iPad or Mac on the same network
// mirrors its screen to this computer (apps/mirroring/airplay.py runs UxPlay
// as the gg-airplay user service). Whether it's on, whether a device has to
// type this computer's code the first time, and full screen or a window.
// Control Center › Screen Mirroring shows who's mirroring and stops it.
import Quickshell
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    headerSymbol: "airplay"; headerTint: "#0a84ff"; headerTitle: "AirPlay Receiver"
    headerText: "Mirror an iPhone, iPad or Mac to this computer, or play its videos here."
    property bool on: false
    property var cfg: ({})
    readonly property bool requirePin: cfg.requirePin !== false
    readonly property string file: sys.gg + "/airplay.json"
    readonly property string register: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/golden-gate/airplay.register"
    property string name: ""
    property bool busy: false
    property bool active: false
    property string error: ""

    function refresh() {
        sys.run(["systemctl", "--user", "is-enabled", "--quiet", "gg-airplay.service"], (out, code) => on = code === 0)
        sys.run(["systemctl", "--user", "is-active", "--quiet", "gg-airplay.service"], (out, code) => active = code === 0)
        sys.run(["sh", "-c", "cat \"$1\" 2>/dev/null", "sh", pane.file], (out) => { try { cfg = JSON.parse(out || "{}") } catch (e) { cfg = ({}) } })
        sys.sh("hostnamectl --pretty 2>/dev/null | grep . || hostname", (out) => name = out.trim())
    }
    Component.onCompleted: refresh()
    // Settings are read when the receiver starts, so a change restarts it.
    function finishService(out, code, err) {
        busy = false
        if (code !== 0) error = "The receiver couldn't apply the change. " + (err || out || "Check that AirPlay support is installed.").trim()
        refresh()
    }
    function restart() {
        if (on) sys.run(["systemctl", "--user", "restart", "gg-airplay.service"], finishService)
        else { busy = false; refresh() }
    }
    function forgetDevices() {
        sys.run(["rm", "-f", register], (out, code, err) => {
            if (code !== 0) { finishService(out, code, err); return }
            restart()
        })
    }
    function save(change, forget) {
        if (busy) return
        busy = true; error = ""
        const next = Object.assign({}, cfg, change)
        sys.writeFile(file, JSON.stringify(next, null, 1) + "\n", "airplay.json", (ok) => {
            if (!ok) { busy = false; error = "The receiver settings couldn't be saved. The previous settings were kept."; return }
            cfg = next
            if (forget) forgetDevices()
            else restart()
        })
    }
    function setOn(value) {
        if (busy) return
        busy = true; error = ""
        sys.run(["systemctl", "--user", value ? "enable" : "disable", "--now", "gg-airplay.service"], finishService)
    }

    Group {
        SetRow {
            title: "AirPlay Receiver"
            subtitle: pane.busy ? "Applying change…" : pane.on && pane.active ? "Shown to iPhone, iPad and Mac as “" + (pane.name || "this computer") + "”" : pane.on ? "Enabled, but the receiver isn't running" : "Off"
            Switch { id: receiverSwitch; objectName: "airplayOn"; enabled: !pane.busy; checked: pane.on; onToggled: (value) => { pane.setOn(value); checked = Qt.binding(() => pane.on) } }
        }
    }
    Group {
        visible: pane.on
        SetRow {
            title: "Require code"
            subtitle: "A device types this computer’s code the first time it connects"
            Switch { objectName: "airplayRequirePin"; enabled: !pane.busy; checked: pane.requirePin; onToggled: (value) => { pane.save({ requirePin: value }); checked = Qt.binding(() => pane.requirePin) } }
        }
        SetRow {
            visible: pane.requirePin && /^\d{4}$/.test(pane.cfg.pin ?? "")
            title: "Code"
            subtitle: "Shown here and in Control Center when a device asks"
            Row {
                spacing: 10
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(pane.cfg.pin ?? "").split("").join(" ")
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: Theme.fs(15); weight: Font.DemiBold }
                }
                // A new code, and devices that used the old one have to type it.
                Button {
                    text: "New Code"
                    enabled: !pane.busy
                    onClicked: {
                        pane.save({ pin: String(Math.floor(Math.random() * 10000)).padStart(4, "0") }, true)
                    }
                }
            }
        }
        SetRow {
            title: "Show in full screen"
            subtitle: "Otherwise the mirrored screen opens in a window"
            Switch { enabled: !pane.busy; checked: pane.cfg.fullScreen === true; onToggled: (value) => { pane.save({ fullScreen: value }); checked = Qt.binding(() => pane.cfg.fullScreen === true) } }
        }
        SetRow {
            title: "Forget devices"
            subtitle: "Every device has to type the code again"
            Button { text: "Forget"; enabled: !pane.busy; onClicked: { pane.busy = true; pane.error = ""; pane.forgetDevices() } }
        }
    }
    Text {
        visible: !!pane.error
        width: parent.width; wrapMode: Text.WordWrap
        text: pane.error; color: Theme.dark ? "#ff453a" : "#d70015"
    }
    Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "To mirror this computer to a TV, open Control Center › Screen Mirroring."
        color: Theme.secondaryLabel
        font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
    }
}
