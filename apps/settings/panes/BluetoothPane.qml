// Bluetooth: power, and your devices (paired ones, connected or not), through
// bluetoothctl.
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    headerSymbol: "bluetooth"; headerTint: "#0a84ff"; headerTitle: "Bluetooth"
    headerText: "Connect to accessories you can use for activities such as streaming music, typing, and gaming."
    property bool powered: false
    property var devices: []        // {mac, name, connected}

    function refresh() {
        sys.sh("bluetoothctl show | grep -q 'Powered: yes' && echo on", (o) => powered = o.trim() === "on")
        sys.sh("bluetoothctl devices Paired; echo ---; bluetoothctl devices Connected", (o) => {
            const [paired, connected] = o.split("---")
            const conn = (connected ?? "").split("\n").map((l) => l.split(" ")[1]).filter((m) => m)
            devices = (paired ?? "").split("\n").filter((l) => l.startsWith("Device ")).map((l) => {
                const p = l.split(" ")
                return { mac: p[1], name: p.slice(2).join(" "), connected: conn.includes(p[1]) }
            })
        })
    }
    Component.onCompleted: refresh()
    Timer { interval: 6000; running: pane.visible; repeat: true; onTriggered: pane.refresh() }

    Group {
        SetRow {
            title: "Bluetooth"; symbol: "bluetooth"; symbolTint: "#0a84ff"
            Switch { checked: pane.powered; onToggled: (on) => { pane.powered = on; pane.sys.run(["bluetoothctl", "power", on ? "on" : "off"], () => pane.refresh()) } }
        }
    }
    Group {
        visible: pane.powered
        title: "My Devices"
        Repeater {
            model: pane.devices
            delegate: SetRow {
                required property var modelData
                title: modelData.name
                subtitle: modelData.connected ? "Connected" : "Not Connected"
                Button {
                    text: modelData.connected ? "Disconnect" : "Connect"
                    onClicked: pane.sys.run(["bluetoothctl", modelData.connected ? "disconnect" : "connect", modelData.mac], () => pane.refresh())
                }
            }
        }
        SetRow { visible: pane.devices.length === 0; title: "No devices"; subtitle: "Put a device in pairing mode, then pair it with bluetoothctl or the Bluetooth menu." }
    }
}
