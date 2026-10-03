// Connect an iPhone: what Messages shows until a phone is paired. One column,
// centred like a Mac setup screen: the Messages icon, what it does, then the
// step at hand (enable Bluetooth for iPhone, find the phone, compare the
// code, turn on the iPhone's two switches).
import Quickshell
import QtQuick
import "../lib"
import "../lib/theme"

Item {
    id: view
    property var pairing
    property bool installed: true
    readonly property var p: pairing
    readonly property bool needsBluetooth: p.checkedAdapter && p.hardwareSupported && !p.bluezReady && p.notificationsSupported

    Flickable {
        anchors.fill: parent
        contentHeight: Math.max(height, column.height + 80)
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: column
            width: Math.min(440, view.width - 60)
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.max(60, (view.height - height) / 2 - 20)
            spacing: 12

            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 96; height: 96
                source: Quickshell.iconPath("org.goldengate.Messages", "internet-chat")
                sourceSize: Qt.size(192, 192)
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "Messages with Your iPhone"
                color: Theme.label
                font { family: Theme.fontDisplay; pixelSize: 24; weight: Font.Bold }
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: "Send and receive iMessage and text messages on this computer through your iPhone, over Bluetooth. Nothing goes through a server, and you don't need to sign in."
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: 13 }
                lineHeight: 1.15
            }
            Item { width: 1; height: 8 }

            // BlueFerry isn't installed (a build without it).
            Text {
                visible: !view.installed
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: "The iPhone connection (BlueFerry) isn't installed. Install blueferry-backend, then open Messages again."
                color: Theme.label
                font { family: Theme.fontUi; pixelSize: 13 }
            }

            // This computer's Bluetooth can't do it.
            Text {
                visible: view.installed && view.p.checkedAdapter && (!view.p.hardwareSupported || !view.p.pairingReady)
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: view.p.issue || "This computer's Bluetooth can't connect to an iPhone. It needs Bluetooth 4.0 or later."
                color: Theme.label
                font { family: Theme.fontUi; pixelSize: 13 }
            }

            // Step 1: Bluetooth needs a restart with the features iPhone needs.
            Button {
                visible: view.installed && view.needsBluetooth && !view.p.pairingNow
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Set Up Bluetooth for iPhone"
                prominent: true
                enabled: !view.p.busy
                onClicked: view.p.enableBluetooth()
            }

            // Step 2: find the phone.
            Glass {
                visible: view.installed && view.p.checkedAdapter && view.p.hardwareSupported && view.p.pairingReady
                    && !view.needsBluetooth && !view.p.pairingNow && !view.p.confirming
                role: "regular"
                width: parent.width
                height: steps.height + 28
                radius: 18
                Column {
                    id: steps
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                    spacing: 10
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "On your iPhone, open Settings › Bluetooth and keep it unlocked nearby."
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: 13 }
                    }
                    Repeater {
                        model: view.p.devices
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: steps.width; height: 40; radius: 9
                            color: view.p.selected === index ? Theme.accent : hoverRow.hovered ? Theme.fill : "transparent"
                            Row {
                                anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                                spacing: 10
                                Symbol { name: "phone"; size: 16; tone: view.p.selected === index ? "white" : "auto"; anchors.verticalCenter: parent.verticalCenter }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: (modelData.name || "iPhone") + (modelData.paired ? "  (paired)" : "")
                                    color: view.p.selected === index ? "#ffffff" : Theme.label
                                    font { family: Theme.fontUi; pixelSize: 13 }
                                }
                            }
                            HoverHandler { id: hoverRow }
                            TapHandler { onTapped: view.p.selected = index }
                        }
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8
                        Button {
                            text: view.p.scanning ? "Stop" : view.p.devices.length ? "Search Again" : "Find My iPhone"
                            prominent: !view.p.devices.length && !view.p.scanning
                            onClicked: view.p.scanning ? view.p.stopScan() : view.p.scan()
                        }
                        Button {
                            visible: view.p.devices.length > 0
                            text: "Connect"
                            prominent: true
                            enabled: view.p.selected >= 0 && !view.p.busy
                            onClicked: view.p.pair()
                        }
                    }
                }
            }

            // Step 3: compare the code on both screens.
            Glass {
                visible: view.p.pairingNow || view.p.confirming
                role: "regular"
                width: parent.width
                height: pairBox.height + 32
                radius: 18
                Column {
                    id: pairBox
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 16 }
                    spacing: 12
                    Text {
                        visible: view.p.passkey !== ""
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: view.p.passkey.replace(/(\d{3})(\d{3})/, "$1 $2")
                        color: Theme.label
                        font { family: Theme.fontDisplay; pixelSize: 38; weight: Font.DemiBold; letterSpacing: 2 }
                    }
                    Row {
                        visible: view.p.confirming
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 8
                        Button { text: "Codes Don't Match"; onClicked: view.p.answer(false) }
                        Button { text: "Codes Match"; prominent: true; onClicked: view.p.answer(true) }
                    }
                    // What's connected so far.
                    Column {
                        visible: !view.p.confirming
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 6
                        Repeater {
                            model: [
                                { key: "map", label: "Messages" },
                                { key: "pbap", label: "Contacts" },
                                { key: "ancs", label: "Group details (Show Message Notifications)" }
                            ]
                            delegate: Row {
                                required property var modelData
                                spacing: 8
                                Symbol {
                                    name: view.p.transports[modelData.key] ? "checkmark" : "clock"
                                    size: 13
                                    tone: view.p.transports[modelData.key] ? "accent" : "gray"
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text { text: modelData.label; color: Theme.label; font { family: Theme.fontUi; pixelSize: 12 } }
                            }
                        }
                    }
                    Text {
                        visible: !view.p.confirming
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: "On your iPhone, tap ⓘ next to this computer in Settings › Bluetooth and turn on Show Message Notifications and Sync Contacts."
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: 11 }
                    }
                }
            }

            Text {
                visible: view.p.status !== ""
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: view.p.status
                color: Theme.secondaryLabel
                font { family: Theme.fontUi; pixelSize: 12 }
            }
            ProgressBar {
                visible: view.p.busy && !view.p.confirming
                anchors.horizontalCenter: parent.horizontalCenter
                width: 160
                indeterminate: true
            }
        }
    }
}
