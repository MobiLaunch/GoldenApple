// The Simulator, as on macOS 27: a frameless window that is just the device,
// with a glass title pill above it (traffic lights, device and OS, Home,
// Save Screen, Rotate) and the device menu.
import Quickshell
import QtQuick
import "../lib"
import "../lib/theme"
import "devices.js" as Devices

FloatingWindow {
    id: win
    property var app
    property var backend
    readonly property var body: Devices.bodySize(app.simDevice, app.simOrientation)
    readonly property real startScale: Math.min(1, ((Quickshell.screens[0]?.height ?? 1000) - 180) / body.h)

    title: "Simulator — " + app.simDevice.name
    color: "transparent"
    implicitWidth: Math.max(440, body.w * startScale + 40)
    implicitHeight: body.h * startScale + 90

    Component.onCompleted: if (app.simPower === "off") app.bootSimulator()

    function close() {
        app.shutDownSimulator()
        app.simulatorOpen = false
    }

    Shortcut { sequence: "Ctrl+Shift+H"; onActivated: win.app.simShowingHome = true }
    Shortcut { sequence: "Ctrl+Left"; onActivated: win.app.rotateSimulator(true) }
    Shortcut { sequence: "Ctrl+Right"; onActivated: win.app.rotateSimulator(false) }
    Shortcut { sequence: "Ctrl+S"; onActivated: win.saveScreen() }
    Shortcut { sequence: "Ctrl+W"; onActivated: win.close() }
    // ⌘Q quits Simulator, not LCode: the two share one process here.
    Shortcut { sequence: "Ctrl+Q"; onActivated: win.close() }

    property string notice: ""
    function saveScreen() {
        device.screenshot((path) => {
            win.notice = path ? "Saved to Pictures" : "Couldn't save the screenshot"
            noticeTimer.restart()
        })
    }
    Timer { id: noticeTimer; interval: 2200; onTriggered: win.notice = "" }

    Item {
        anchors.fill: parent

        // Title pill: drag it to move the window.
        Item {
            id: titleBar
            anchors.horizontalCenter: parent.horizontalCenter
            y: 6
            width: Math.min(parent.width - 12, 420)
            height: 44
            Glass {
                anchors.fill: parent
                radius: height / 2
                role: "regular"
            }
            DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
            TrafficLights {
                id: lights
                x: 16
                anchors.verticalCenter: parent.verticalCenter
                canZoom: false
                closeAction: () => win.close()
            }
            Column {
                anchors { left: lights.right; leftMargin: 14; right: buttons.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                Text {
                    width: parent.width
                    text: win.app.simDevice.name
                    elide: Text.ElideRight
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold }
                }
                Text {
                    width: parent.width
                    text: win.notice || (win.app.simPower === "booting" ? "Booting…" : Devices.OS_NAME + " " + Devices.OS_VERSION)
                    elide: Text.ElideRight
                    color: win.app.simError ? "#ff453a" : Theme.secondaryLabel
                    font { family: Theme.fontUi; pixelSize: 11 }
                }
            }
            Row {
                id: buttons
                anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                spacing: 0
                ToolbarButton { symbol: "house"; symbolSize: 16; Accessible.name: "Home (⇧⌘H)"; onClicked: win.app.simShowingHome = true }
                ToolbarButton { symbol: "screenshot"; symbolSize: 16; Accessible.name: "Save Screen (⌘S)"; onClicked: win.saveScreen() }
                ToolbarButton { symbol: "rotate-left"; symbolSize: 16; Accessible.name: "Rotate Left (⌘←)"; onClicked: win.app.rotateSimulator(true) }
                ToolbarButton { symbol: "rotate-right"; symbolSize: 16; Accessible.name: "Rotate Right (⌘→)"; onClicked: win.app.rotateSimulator(false) }
                ToolbarButton {
                    id: deviceButton
                    symbol: win.app.simDevice.tablet ? "tablet" : "smartphone"
                    symbolSize: 16
                    Accessible.name: "Choose Device"
                    onClicked: menu.popup(deviceButton, deviceButton.width - 230, deviceButton.height + 6,
                        [{ header: "Device" }].concat(win.app.devices.map((d) => ({
                            text: d.name, symbol: d.tablet ? "tablet" : "smartphone", checked: d.id === win.app.simDeviceId,
                            action: () => win.app.setSimDevice(d.id) })),
                        [{ separator: true },
                         { text: "Erase All Content and Settings…", action: () => { win.app.installedApps = []; win.app.simShowingHome = true } },
                         { text: win.app.simPower === "off" ? "Boot" : "Shut Down",
                           action: () => win.app.simPower === "off" ? win.app.bootSimulator() : win.app.shutDownSimulator() }]))
                }
            }
        }

        DeviceView {
            id: device
            anchors { top: titleBar.bottom; left: parent.left; right: parent.right; bottom: parent.bottom; topMargin: 4 }
            app: win.app
            backend: win.backend
        }

        Text {
            anchors.centerIn: device
            visible: !!win.app.simError
            width: 300
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: win.app.simError
            color: "#ffffff"
            font { family: Theme.fontUi; pixelSize: 13 }
        }

        Item {
            id: overlay
            anchors.fill: parent
            z: 10
        }
    }

    PopupMenu { id: menu; parent: overlay; menuWidth: 240 }
}
