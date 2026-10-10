// First-party AirPods connection card. No separate CitronPods GUI or Dock
// icon: the system shell owns the transient surface and the M10 daemon owns
// all Bluetooth, L2CAP, D-Bus and battery telemetry.
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import "ui" as Shared
import "ui/theme"
import "components"

PanelWindow {
    id: pop
    objectName: "citronPodsSystemPopup"
    property bool open: false
    property string announcedAddress: ""
    readonly property var active: {
        if (!announcedAddress) return pods.activeDevice
        return pods.devices.find((v) => v.address === announcedAddress) ??
               ({name:"AirPods", address:announcedAddress, paired:false, connected:false})
    }
    readonly property bool connected: active.connected === true
    screen: Quickshell.screens[0]
    anchors { top: true; right: true }
    margins { top: 46; right: 14 }
    implicitWidth: Math.min(370, (screen?.width ?? 800) - 28)
    implicitHeight: pods.canControl ? 378 : 334
    color: "transparent"
    WlrLayershell.namespace: "gg-citronpods"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    visible: open || dismissDelay.running
    mask: Region { item: card }
    DesktopBackdrop { surface: pop; namespace: "gg-citronpods" }

    Shared.CitronPodsService {
        id: pods
        onPopupRequested: (address) => {
            if (pods.state.autoPopupEnabled !== false) pop.showFor(address)
        }
        onConnectedTransition: (device) => {
            // Backwards compatibility with a daemon not emitting popupSequence.
            if (!pods.snapshotValid && pods.state.autoPopupEnabled !== false)
                pop.showFor(device.address)
        }
    }
    function showFor(address) {
        if (address) announcedAddress = address
        open = true
        dismissDelay.restart()
    }
    function dismiss() { dismissDelay.stop(); open = false }
    Timer {
        id: dismissDelay
        interval: 7500
        onTriggered: {
            if (pods.state.busy === true) restart()
            else pop.open = false
        }
    }
    IpcHandler {
        target: "citronpods"
        function show(): void { pop.showFor("") }
        function hide(): void { pop.dismiss() }
    }

    Shared.Glass {
        id: card
        x: 5; y: 5
        width: parent.width - 10
        height: parent.height - 10
        radius: 27; role: "menu"
        shadowEnabled: false
        tint: Theme.dark ? "#df1b1d23" : "#eff9f9fc"
        opacity: pop.open ? 1 : 0
        scale: pop.open ? 1 : 0.965
        Behavior on opacity { enabled: !Prefs.reduceMotion; NumberAnimation { duration: 165; easing.type: Easing.OutCubic } }
        Behavior on scale { enabled: !Prefs.reduceMotion; NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

        ColumnLayout {
            anchors { fill: parent; margins: 21 }
            spacing: 10
            RowLayout {
                Layout.fillWidth: true
                Shared.Symbol { name: "bluetooth"; size: 21; tone: "auto" }
                Text {
                    Layout.fillWidth: true
                    text: "AirPods"
                    color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: Font.DemiBold }
                }
                Text {
                    text: "×"; color: Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: Theme.fs(22) }
                    MouseArea { anchors.fill: parent; onClicked: pop.dismiss() }
                }
            }
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 83
                // Original CitronPods M10 silhouettes: Pro, classic, and Max.
                // Local SVG assets; no network fetch or proprietary icon font.
                Image {
                    id: podArt
                    anchors.centerIn: parent
                    width: Math.min(parent.width, 243)
                    height: parent.height
                    source: {
                        const name = String(pop.active.name ?? "").toLowerCase()
                        const kind = name.includes("max") ? "airpods-max.svg"
                            : name.includes("pro") ? "airpods-pro.svg" : "airpods-classic.svg"
                        return Qt.resolvedUrl("assets/citronpods/" + kind)
                    }
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    sourceSize: Qt.size(486, 254)
                }
                Shared.Symbol {
                    visible: podArt.status === Image.Error
                    anchors.centerIn: parent
                    name: "headphones"; size: 56; tone: "auto"
                }
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: pop.active.name || "AirPods"
                color: Theme.label
                font { family: Theme.fontDisplay; pixelSize: Theme.fs(18); weight: Font.DemiBold }
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: pods.state.busy ? "Connecting…" : !pods.online ? "CitronPods service unavailable"
                    : pop.connected ? "Connected" : pop.active.paired ? "Not connected" : "Pair in Bluetooth Settings"
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: [
                        {label:"Left", value:pop.active.leftBattery},
                        {label:"Right", value:pop.active.rightBattery},
                        {label:"Case", value:pop.active.caseBattery}
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        height: 52; radius: 15
                        color: Theme.dark ? "#20ffffff" : "#16000000"
                        Column {
                            anchors.centerIn: parent
                            spacing: 3
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: modelData.label
                                color: Theme.secondaryLabel
                                font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: typeof modelData.value === "number" && modelData.value >= 0 &&
                                      modelData.value <= 100 ? modelData.value + "%" : "—"
                                color: Theme.label
                                font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.DemiBold }
                            }
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: pods.canControl
                Repeater {
                    model: ["Off", "ANC", "Transparency", "Adaptive"]
                    delegate: Rectangle {
                        id: noiseChip
                        required property string modelData
                        required property int index
                        Layout.fillWidth: true
                        height: 31; radius: height / 2
                        color: pods.state.noiseMode === index ? Theme.accent
                             : Theme.dark ? "#30ffffff" : "#15000000"
                        Behavior on color { enabled: !Prefs.reduceMotion; ColorAnimation { duration: 140 } }
                        Text {
                            anchors.centerIn: parent
                            text: noiseChip.modelData
                            color: pods.state.noiseMode === noiseChip.index ? "#ffffff" : Theme.label
                            font { family: Theme.fontUi; pixelSize: Theme.fs(11); weight: Font.Medium }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: pods.setNoiseMode(noiseChip.index)
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 9
                Rectangle {
                    Layout.fillWidth: true
                    height: 34; radius: height / 2
                    color: Theme.fill
                    Text {
                        anchors.centerIn: parent
                        text: "Settings"
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: Font.Medium }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: { pop.dismiss(); Quickshell.execDetached(["gg-settings","airpods"]) }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    height: 34; radius: height / 2
                    color: Theme.accent
                    Text {
                        anchors.centerIn: parent
                        text: pop.connected ? "Done" : "Connect"
                        color: "white"
                        font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: Font.DemiBold }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (pop.connected) pop.dismiss()
                            else if (pop.active.address) pods.connectDevice(pop.active.address)
                            else { pop.dismiss(); Quickshell.execDetached(["gg-settings","bluetooth"]) }
                        }
                    }
                }
            }
        }
    }
}
