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
    property var nearby: []
    property bool discovering: false
    property string busyMac: ""

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
    function scan() {
        discovering = true
        sys.run(["bluetoothctl", "--timeout", "7", "scan", "on"], () => {
            sys.sh("bluetoothctl devices | grep '^Device '", (o) => {
                const known = devices.map(d => d.mac)
                nearby = o.split("\\n").filter(l => l.startsWith("Device ")).map(l => {
                    const p = l.split(" "); return { mac: p[1], name: p.slice(2).join(" ") }
                }).filter(d => !known.includes(d.mac))
                discovering = false
            })
        })
    }
    function pair(d) {
        busyMac = d.mac
        sys.sh("bluetoothctl pair " + d.mac + " && bluetoothctl trust " + d.mac + " && bluetoothctl connect " + d.mac,
               (o, code) => { busyMac = ""; if (code === 0) { nearby = nearby.filter(x => x.mac !== d.mac); refresh() } })
    }
    Component.onCompleted: { refresh(); if (powered) scan() }
    Timer { interval: 6000; running: pane.visible; repeat: true; onTriggered: pane.refresh() }

    Group {
        SetRow {
            title: "Bluetooth"; symbol: "bluetooth"; symbolTint: "#0a84ff"
            Switch { checked: pane.powered; onToggled: (on) => { pane.powered = on; pane.sys.run(["bluetoothctl", "power", on ? "on" : "off"], () => { pane.refresh(); if (on) pane.scan() }) } }
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
        SetRow { visible: pane.devices.length === 0; title: "No paired devices"; subtitle: "Put an accessory in pairing mode to connect it." }
    }
    Group {
        visible: pane.powered
        title: "Nearby Devices"
        Repeater {
            model: pane.nearby
            delegate: SetRow {
                required property var modelData
                title: modelData.name || modelData.mac
                subtitle: modelData.mac
                Button { text: pane.busyMac === modelData.mac ? "Connecting…" : "Connect"; enabled: !pane.busyMac; onClicked: pane.pair(modelData) }
            }
        }
        SetRow {
            title: pane.discovering ? "Looking for accessories…" : (pane.nearby.length ? "Scan Again" : "No accessories found")
            Button { text: "Scan"; enabled: !pane.discovering; onClicked: pane.scan() }
        }
    }
}
