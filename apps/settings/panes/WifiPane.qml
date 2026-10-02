// Wi-Fi: the radio, the network you're on, and the others nearby (join, with
// the password asked in place). NetworkManager through nmcli.
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    headerSymbol: "wifi"; headerTint: "#0a84ff"; headerTitle: "Wi-Fi"
    headerText: "Set up Wi-Fi to wirelessly connect this computer to the internet."
    property bool radio: true
    property var networks: []
    property string joining: ""
    property string error: ""

    function fields(line) {
        const out = []; let cur = ""
        for (let i = 0; i < line.length; i++) {
            const c = line[i]
            if (c === "\\" && i + 1 < line.length) { cur += line[++i]; continue }
            if (c === ":") { out.push(cur); cur = ""; continue }
            cur += c
        }
        out.push(cur); return out
    }
    function refresh() {
        sys.run(["nmcli", "-t", "radio", "wifi"], (o) => radio = o.trim() === "enabled")
        sys.run(["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list", "--rescan", "auto"], (o) => {
            const best = {}
            for (const line of o.split("\n")) {
                const f = fields(line)
                if (!f[1]) continue
                const n = { ssid: f[1], signal: Number(f[2]) || 0, secure: !!f[3] && f[3] !== "--", active: f[0] === "*" }
                if (!best[n.ssid] || n.signal > best[n.ssid].signal || n.active) best[n.ssid] = n
            }
            networks = Object.values(best).sort((a, b) => (b.active - a.active) || (b.signal - a.signal))
        })
    }
    Component.onCompleted: refresh()
    Timer { interval: 10000; running: pane.visible && !pane.joining; repeat: true; onTriggered: pane.refresh() }
    function join(ssid, password) {
        error = ""
        sys.run(password ? ["nmcli", "device", "wifi", "connect", ssid, "password", password] : ["nmcli", "device", "wifi", "connect", ssid],
                (o, code) => { if (code === 0) { joining = ""; refresh() } else error = "Couldn't join “" + ssid + "”." })
    }
    readonly property var current: networks.find((n) => n.active) ?? null

    Group {
        SetRow {
            title: "Wi-Fi"; symbol: "wifi"; symbolTint: "#0a84ff"
            Switch { checked: pane.radio; onToggled: (on) => { pane.radio = on; pane.sys.run(["nmcli", "radio", "wifi", on ? "on" : "off"], () => pane.refresh()) } }
        }
        SetRow {
            visible: pane.radio && !!pane.current
            title: pane.current?.ssid ?? ""
            subtitle: "Connected"
            Symbol { name: "lock"; size: 13; visible: !!pane.current?.secure; opacity: 0.6 }
            Symbol { name: "wifi"; size: 15 }
        }
    }
    Group {
        visible: pane.radio
        title: "Other Networks"
        Repeater {
            model: pane.networks.filter((n) => !n.active)
            delegate: Column {
                id: networkBlock
                required property var modelData
                width: parent ? parent.width : 500

                SetRow {
                    id: netRow
                    width: networkBlock.width
                    title: networkBlock.modelData.ssid
                    chevron: false
                    Symbol { name: "lock"; size: 13; visible: networkBlock.modelData.secure; opacity: 0.6 }
                    Symbol { name: "wifi"; size: 15; opacity: 0.35 + 0.65 * Math.min(1, networkBlock.modelData.signal / 80) }
                    Button {
                        text: pane.joining === networkBlock.modelData.ssid ? "Cancel" : "Connect"
                        onClicked: {
                            pane.error = ""
                            if (pane.joining === networkBlock.modelData.ssid) { pane.joining = ""; return }
                            if (networkBlock.modelData.secure) pane.joining = networkBlock.modelData.ssid
                            else pane.join(networkBlock.modelData.ssid)
                        }
                    }
                }

                // Keep credentials visually attached to the network being joined.
                // The old global row appeared below the entire scan result list.
                SetRow {
                    width: networkBlock.width
                    visible: pane.joining === networkBlock.modelData.ssid
                    title: "Password"
                    subtitle: pane.error
                    TextField {
                        id: pw
                        width: 180
                        password: true
                        placeholder: "Password"
                        onAccepted: pane.join(networkBlock.modelData.ssid, text)
                    }
                    Button {
                        text: "Join"
                        prominent: true
                        onClicked: pane.join(networkBlock.modelData.ssid, pw.text)
                    }
                }
            }
        }
        SetRow {
            visible: pane.networks.filter((n) => !n.active).length === 0
            title: "No other networks found"
        }
    }
}
