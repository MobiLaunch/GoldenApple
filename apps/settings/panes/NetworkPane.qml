// Network: each interface with its state and address, as NetworkManager sees it.
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    property var devices: []     // {name, type, state, connection, ip}
    function refresh() {
        sys.sh("nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device; echo ---; for d in $(nmcli -t -f DEVICE device); do printf '%s ' \"$d\"; nmcli -g IP4.ADDRESS device show \"$d\" | head -n1; done", (o) => {
            const [list, ips] = o.split("---")
            const ip = {}
            for (const l of (ips ?? "").split("\n")) { const p = l.trim().split(" "); if (p[0]) ip[p[0]] = p[1] ?? "" }
            devices = (list ?? "").split("\n").filter((l) => l && !l.startsWith("lo:")).map((l) => {
                const f = l.split(":")
                return { name: f[0], type: f[1], state: f[2], connection: f[3], ip: ip[f[0]] ?? "" }
            }).filter((d) => ["ethernet", "wifi", "wireguard", "vpn", "bridge", "tun"].includes(d.type))
        })
    }
    Component.onCompleted: refresh()

    Group {
        Repeater {
            model: pane.devices
            delegate: SetRow {
                required property var modelData
                readonly property bool up: modelData.state === "connected"
                title: modelData.type === "wifi" ? "Wi-Fi" : modelData.type === "ethernet" ? "Ethernet" : modelData.type.toUpperCase() + " (" + modelData.name + ")"
                subtitle: up ? "Connected" + (modelData.ip ? " · " + modelData.ip.split("/")[0] : "") : modelData.state === "unavailable" ? "Not connected" : modelData.state
                symbol: modelData.type === "wifi" ? "wifi" : "globe"
                symbolTint: "#0a84ff"
                Rectangle { width: 9; height: 9; radius: 4.5; color: up ? "#34c759" : "#ff3b30" }
            }
        }
        SetRow { visible: pane.devices.length === 0; title: "No network interfaces" }
    }
}
