// Settings ▸ Simulators: the device the Simulator starts with, and your own
// devices — any screen size, phone or tablet, with the hardware you choose.
import QtQuick
import "../../lib"
import "../../lib/theme"
import "../devices.js" as Devices

Page {
    id: page
    readonly property var customDevices: app.settings.customDevices || []
    property int newKind: 0                 // phone, tablet
    property int newStyle: 0                // index in Devices.STYLES
    property string error: ""

    function addDevice() {
        const name = nameField.text.trim()
        const w = parseInt(widthField.text, 10), h = parseInt(heightField.text, 10)
        if (!name) { error = "Give the device a name."; return }
        if (!(w >= 240 && w <= 2048 && h >= 240 && h <= 2048)) { error = "Width and height are in points, from 240 to 2048."; return }
        if (app.devices.some((d) => d.name.toLowerCase() === name.toLowerCase())) { error = "There's already a device called “" + name + "”."; return }
        error = ""
        const spec = { id: "custom-" + name.toLowerCase().replace(/[^a-z0-9]+/g, "-") + "-" + Date.now().toString(36),
                       name: name, width: w, height: h, tablet: newKind === 1, style: Devices.STYLES[newStyle] }
        app.saveSettings({ customDevices: customDevices.concat([spec]) })
        nameField.text = ""
    }
    function removeDevice(id) {
        const values = { customDevices: customDevices.filter((d) => d.id !== id) }
        if (app.settings.defaultSimulator === id) values.defaultSimulator = "lphone-16"
        app.saveSettings(values)
    }

    FormRow {
        label: "Start With"
        detail: "The device the Simulator boots when you open it."
        PopUpButton {
            options: page.app.devices.map((d) => d.name)
            current: Math.max(0, page.app.devices.findIndex((d) => d.id === page.app.settings.defaultSimulator))
            menuParent: page.overlay
            onPicked: (i) => page.app.saveSettings({ defaultSimulator: page.app.devices[i].id })
        }
    }
    FormGap {}
    SidebarSection { text: "Devices"; leftPadding: 0; topSpacing: 0 }
    Rectangle {
        width: parent.width
        height: devices.height + 12
        radius: 10
        color: Theme.dark ? "#10ffffff" : "#06000000"
        border { width: 1; color: Theme.separator }
        Column {
            id: devices
            x: 6; y: 6
            width: parent.width - 12
            Repeater {
                model: page.app.devices
                delegate: Item {
                    id: devRow
                    required property var modelData
                    width: devices.width
                    height: 34
                    Symbol { x: 8; anchors.verticalCenter: parent.verticalCenter; name: devRow.modelData.tablet ? "tablet" : "smartphone"; size: 18; tone: devRow.modelData.custom ? "accent" : "gray" }
                    Text {
                        x: 36
                        anchors.verticalCenter: parent.verticalCenter
                        text: devRow.modelData.name
                        color: Theme.label
                        font { family: Theme.fontUi; pixelSize: 13 }
                    }
                    Text {
                        anchors { right: parent.right; rightMargin: devRow.modelData.custom ? 40 : 12; verticalCenter: parent.verticalCenter }
                        text: devRow.modelData.width + " × " + devRow.modelData.height + " pt  ·  "
                            + ({ island: "Dynamic Island", "home-button": "Home Button", none: "No Cutout" })[devRow.modelData.cutout]
                        color: Theme.secondaryLabel
                        font { family: Theme.fontUi; pixelSize: 12 }
                    }
                    ToolbarButton {
                        visible: !!devRow.modelData.custom
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        symbol: "trash"
                        symbolSize: 13
                        Accessible.name: "Remove " + devRow.modelData.name
                        onClicked: page.removeDevice(devRow.modelData.id)
                    }
                }
            }
        }
    }
    FormGap {}
    SidebarSection { text: "Add a Device"; leftPadding: 0; topSpacing: 0 }
    FormRow {
        label: "Name"
        TextField { id: nameField; width: 260; height: 28; placeholder: "My Phone" }
    }
    FormRow {
        label: "Screen Size"
        detail: "In points, portrait. A 6.1-inch phone is about 393 × 852; an 11-inch tablet about 820 × 1180."
        Row {
            spacing: 8
            TextField { id: widthField; width: 80; height: 28; text: "393"; input.validator: IntValidator { bottom: 1; top: 4096 } }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "×"; color: Theme.secondaryLabel; font { family: Theme.fontUi; pixelSize: 13 } }
            TextField { id: heightField; width: 80; height: 28; text: "852"; input.validator: IntValidator { bottom: 1; top: 4096 } }
        }
    }
    FormRow {
        label: "Kind"
        Segmented { width: 180; options: ["Phone", "Tablet"]; current: page.newKind; onPicked: (i) => page.newKind = i }
    }
    FormRow {
        label: "Hardware"
        Segmented { width: 330; options: ["Dynamic Island", "Home Button", "No Cutout"]; current: page.newStyle; onPicked: (i) => page.newStyle = i }
    }
    FormRow {
        label: ""
        detail: page.error
        Button { text: "Add Device"; prominent: true; onClicked: page.addDevice() }
    }
}
