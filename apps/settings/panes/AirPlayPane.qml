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

    function refresh() {
        sys.run(["systemctl", "--user", "is-enabled", "--quiet", "gg-airplay.service"], (out, code) => on = code === 0)
        sys.run(["sh", "-c", "cat \"$1\" 2>/dev/null", "sh", pane.file], (out) => { try { cfg = JSON.parse(out || "{}") } catch (e) { cfg = ({}) } })
        sys.sh("hostnamectl --pretty 2>/dev/null | grep . || hostname", (out) => name = out.trim())
    }
    Component.onCompleted: refresh()
    // Settings are read when the receiver starts, so a change restarts it.
    function save(change) {
        const next = Object.assign({}, cfg, change)
        cfg = next
        sys.writeFile(file, JSON.stringify(next, null, 1) + "\n", "airplay.json", () => {
            if (on) sys.run(["systemctl", "--user", "restart", "gg-airplay.service"])
        })
    }
    function setOn(value) {
        on = value
        sys.run(["systemctl", "--user", value ? "enable" : "disable", "--now", "gg-airplay.service"])
    }

    Group {
        SetRow {
            title: "AirPlay Receiver"
            subtitle: pane.on ? "Shown to iPhone, iPad and Mac as “" + (pane.name || "this computer") + "”" : "Off"
            Switch { objectName: "airplayOn"; checked: pane.on; onToggled: (value) => pane.setOn(value) }
        }
    }
    Group {
        visible: pane.on
        SetRow {
            title: "Require code"
            subtitle: "A device types this computer’s code the first time it connects"
            Switch { objectName: "airplayRequirePin"; checked: pane.requirePin; onToggled: (value) => pane.save({ requirePin: value }) }
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
                    onClicked: {
                        pane.save({ pin: String(Math.floor(Math.random() * 10000)).padStart(4, "0") })
                        sys.run(["rm", "-f", pane.register])
                    }
                }
            }
        }
        SetRow {
            title: "Show in full screen"
            subtitle: "Otherwise the mirrored screen opens in a window"
            Switch { checked: pane.cfg.fullScreen === true; onToggled: (value) => pane.save({ fullScreen: value }) }
        }
        SetRow {
            title: "Forget devices"
            subtitle: "Every device has to type the code again"
            Button { text: "Forget"; onClicked: { sys.run(["rm", "-f", pane.register]); if (pane.on) sys.run(["systemctl", "--user", "restart", "gg-airplay.service"]) } }
        }
    }
    Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "To mirror this computer to a TV, open Control Center › Screen Mirroring."
        color: Theme.secondaryLabel
        font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
    }
}
