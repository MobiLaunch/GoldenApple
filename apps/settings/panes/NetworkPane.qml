// NetworkManager's real interfaces, with working Ethernet connect/disconnect.
// Wi-Fi pairing and passwords remain in the full Wi-Fi pane.
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    headerSymbol: "globe"; headerTint: "#0a84ff"; headerTitle: "Network"
    headerText: "View your network connections and manage wired networking."
    property var devices: []
    property string error: ""
    property string working: ""
    function parseFields(line) {
        // nmcli's terse format escapes colons and backslashes, including in
        // Wi-Fi names; plain .split(":") would silently corrupt connection data.
        const fields = []
        let text = "", escaped = false
        for (const char of line) {
            if (escaped) { text += char; escaped = false }
            else if (char === "\\") escaped = true
            else if (char === ":") { fields.push(text); text = "" }
            else text += char
        }
        fields.push(text)
        return fields
    }
    function refresh() {
        sys.run(["nmcli", "-t", "--escape", "yes", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device"],
            (output, code) => {
                if (code !== 0) {
                    error = "NetworkManager is not available."
                    return
                }
                const rows = output.split("\n").filter((s) => s)
                    .map(parseFields)
                    .map((f) => ({ name: f[0], type: f[1], state: f[2], connection: f[3] }))
                    .filter((d) => !!d.name && d.name !== "lo" && ["ethernet", "wifi", "wireguard", "vpn", "bridge", "tun"].includes(d.type))
                devices = rows
                if (!working) error = ""
            })
    }
    function connect(dev, enable) {
        if (working) return
        working = dev
        error = ""
        sys.run(["nmcli", "device", enable ? "connect" : "disconnect", dev], (output, code, err) => {
            working = ""
            if (code !== 0) error = (err || output || "Could not change the network connection.").trim()
            refresh()
        })
    }
    Component.onCompleted: refresh()
    Timer { interval: 12000; running: pane.visible; repeat: true; onTriggered: if (!pane.working) pane.refresh() }

    Group {
        title: "Network Interfaces"
        Repeater {
            model: pane.devices
            delegate: SetRow {
                id: device
                required property var modelData
                readonly property bool up: modelData.state === "connected"
                title: modelData.type === "wifi" ? "Wi-Fi" : modelData.type === "ethernet" ? "Ethernet" :
                    modelData.type.toUpperCase() + " (" + modelData.name + ")"
                subtitle: (up ? "Connected" : modelData.state === "unavailable" ? "Not connected" : modelData.state)
                    + (modelData.connection && modelData.connection !== "--" ? " · " + modelData.connection : "")
                symbol: modelData.type === "wifi" ? "wifi" : "globe"
                symbolTint: "#0a84ff"
                Rectangle { width: 9; height: 9; radius: 4.5; color: device.up ? "#34c759" : "#ff9f0a" }
                Button {
                    visible: device.modelData.type === "ethernet"
                    enabled: !pane.working && device.modelData.state !== "unavailable"
                    text: pane.working === device.modelData.name ? "Working…" : device.up ? "Disconnect" : "Connect"
                    onClicked: pane.connect(device.modelData.name, !device.up)
                }
                Button {
                    visible: device.modelData.type === "wifi"
                    text: "Details…"
                    onClicked: pane.nav.open("wifi")
                }
            }
        }
        SetRow { visible: pane.devices.length === 0; title: "No network interfaces"; subtitle: pane.error || "Connect a network adapter to continue." }
    }
    Group {
        visible: !!pane.error && pane.devices.length > 0
        SetRow {
            title: "Network Error"
            subtitle: pane.error
            Button { text: "Retry"; onClicked: pane.refresh() }
        }
    }
}
