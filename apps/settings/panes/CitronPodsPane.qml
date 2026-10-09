// AirPods are configured inside Golden Gate Settings, not a standalone app.
// Requires the M10 CitronPods daemon; if absent show an actionable status,
// never made-up battery/ANC values or a fake connection.
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    headerSymbol: "bluetooth"
    headerTint: "#0a84ff"
    headerTitle: "AirPods"
    headerText: "Connect your AirPods, view their reported battery levels and adjust supported features."
    CitronPodsService { id: pods; enabled: pane.visible }
    readonly property var device: pods.activeDevice
    readonly property string address: String(device.address ?? "")
    readonly property bool paired: device.paired === true
    function battery(value) {
        return typeof value === "number" && Number.isFinite(value) && value >= 0 && value <= 100
               ? value + "%" : "Unavailable"
    }

    Group {
        title: "My AirPods"
        SetRow {
            title: pane.device.name || "No AirPods selected"
            subtitle: pods.state.busy ? ("Working… " + (pods.state.operation ?? "")) : pods.status
            symbol: "bluetooth"; symbolTint: "#0a84ff"
            Button {
                visible: !!pane.address
                enabled: pods.online && pods.state.busy !== true
                text: pods.connected ? "Disconnect" : pane.paired ? "Connect" : "Pair"
                onClicked: pods.connected ? pods.disconnectDevice(pane.address) : pods.connectDevice(pane.address)
            }
        }
        SetRow {
            title: "CitronPods engine"
            subtitle: pods.online ? String(pods.state.protocolStatus ?? "Connected to the system service") :
                      "Not running. Install the M10 engine or start the user service."
            Button {
                text: pods.online ? "Refresh" : "Start"
                onClicked: pods.online ? pods.refresh() :
                    pane.sys.run(["systemctl", "--user", "start", "citronpods-daemon.service"], () => pods.refresh())
            }
        }
        SetRow {
            title: "Find AirPods"
            subtitle: "Search paired and nearby accessories; unpaired advertisements are not verified."
            Button {
                text: pods.state.scanning ? "Stop Scan" : "Scan"
                enabled: pods.online
                onClicked: pods.state.scanning ? pods.stopDiscovery() : pods.startDiscovery()
            }
        }
        Repeater {
            model: pods.devices
            delegate: SetRow {
                required property var modelData
                title: modelData.name || "AirPods"
                subtitle: modelData.connected ? "Connected" : modelData.paired ? "Paired" : "Not connected"
                Button {
                    text: modelData.address === pane.address ? "Selected" : "Select"
                    enabled: modelData.address !== pane.address
                    onClicked: pods.select(modelData.address)
                }
            }
        }
    }

    Group {
        title: "Battery"
        SetRow { title: "Left AirPod"; subtitle: pane.battery(pane.device.leftBattery) }
        SetRow { title: "Right AirPod"; subtitle: pane.battery(pane.device.rightBattery) }
        SetRow { title: "Charging Case"; subtitle: pane.battery(pane.device.caseBattery) }
    }
    Group {
        title: "Noise Control"
        SetRow {
            title: "Listening Mode"
            subtitle: pods.canControl ? "Changes the mode on your AirPods" : "Requires a connected, supported AirPods protocol"
            Row {
                spacing: 5
                Repeater {
                    model: ["Off", "Noise Cancellation", "Transparency", "Adaptive"]
                    delegate: Button {
                        required property string modelData
                        required property int index
                        text: modelData
                        enabled: pods.canControl
                        prominent: pods.state.noiseMode === index
                        onClicked: pods.setNoiseMode(index)
                    }
                }
            }
        }
        SetRow {
            title: "Conversation Awareness"
            subtitle: "Reduce playback volume when you speak, where supported."
            Switch {
                enabled: pods.canControl
                checked: pods.state.conversationalAwareness === true
                onToggled: (value) => pods.setConversationAwareness(value)
            }
        }
    }
    Group {
        title: "Connection & Playback"
        SetRow {
            title: "Use AirPods for Sound"
            subtitle: String(pods.state.audioStatus ?? "Route audio through PipeWire")
            Switch {
                enabled: pods.online
                checked: pods.state.routeAudio === true
                onToggled: (value) => pods.setRouteAudio(value)
            }
        }
        SetRow {
            title: "Automatic Ear Detection"
            Switch {
                enabled: pods.online
                checked: pods.state.automaticEarDetection === true
                onToggled: (value) => pods.setEarDetection(value)
            }
        }
        SetRow {
            title: "Connection Card"
            subtitle: "Show the system glass card when trusted AirPods connect."
            Switch {
                enabled: pods.online
                checked: pods.state.autoPopupEnabled !== false
                onToggled: (value) => pods.setAutoPopup(value)
            }
        }
    }
    Group {
        title: "Nearby Accessories · Unverified"
        visible: pods.state.scanning === true || pods.nearby.length > 0
        SetRow {
            title: "BLE discovery"
            subtitle: "Nearby device advertisements can be spoofed. Confirm the device in Bluetooth Settings."
            Button { text: "Bluetooth Settings"; onClicked: pane.nav.open("bluetooth") }
        }
        Repeater {
            model: pods.nearby
            delegate: SetRow {
                required property var modelData
                title: modelData.model || "Unknown AirPods"
                subtitle: "Nearby signal " + (modelData.rssi ?? "?") + " dBm · unverified"
            }
        }
    }
}
