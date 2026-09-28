// Battery: charge, state and health from UPower; energy mode through
// power-profiles-daemon where it's installed.
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    property var info: ({})
    property bool hasBattery: false
    property string profile: ""
    function refresh() {
        sys.sh("b=$(upower -e | grep -m1 BAT); [ -n \"$b\" ] && upower -i \"$b\"", (o) => {
            const i = {}
            for (const l of o.split("\n")) { const m = /^\s*([\w-]+(?: [\w-]+)*):\s+(.*)$/.exec(l); if (m) i[m[1]] = m[2] }
            info = i
            hasBattery = !!i.percentage
        })
        sys.sh("command -v powerprofilesctl >/dev/null && powerprofilesctl get", (o) => profile = o.trim())
    }
    Component.onCompleted: refresh()
    Timer { interval: 20000; running: pane.visible; repeat: true; onTriggered: pane.refresh() }

    Group {
        visible: pane.hasBattery
        SetRow {
            title: "Battery Level"
            subtitle: (pane.info.state ?? "").replace(/-/g, " ")
            Text { text: pane.info.percentage ?? ""; color: Theme.label; font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold } }
            Rectangle {
                width: 34; height: 16; radius: 4
                color: "transparent"; border { width: 1; color: Theme.secondaryLabel }
                Rectangle {
                    x: 2; y: 2; height: 12; radius: 2
                    width: 30 * (parseFloat(pane.info.percentage) || 0) / 100
                    color: (parseFloat(pane.info.percentage) || 0) < 20 ? "#ff3b30" : "#34c759"
                }
            }
        }
        SetRow { title: "Battery Health"; Text { text: pane.info.capacity ? (parseFloat(pane.info.capacity) >= 80 ? "Normal" : "Service Recommended") + " (" + Math.round(parseFloat(pane.info.capacity)) + "%)" : "—"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 13 } } }
        SetRow { visible: !!pane.info["time to empty"]; title: "Time Remaining"; Text { text: pane.info["time to empty"] ?? ""; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 13 } } }
    }
    Group {
        visible: !!pane.profile
        SetRow {
            title: "Energy Mode"
            subtitle: "Low Power saves battery; High Power favours performance."
            PopUpButton {
                menuParent: pane.nav.overlay
                options: ["Low Power", "Automatic", "High Power"]
                current: ({ "power-saver": 0, "balanced": 1, "performance": 2 })[pane.profile] ?? 1
                onPicked: (i) => { pane.profile = ["power-saver", "balanced", "performance"][i]; pane.sys.run(["powerprofilesctl", "set", pane.profile]) }
            }
        }
    }
    Group {
        visible: !pane.hasBattery
        SetRow { title: "This computer has no battery"; subtitle: "It's running on power from the wall." }
    }
}
