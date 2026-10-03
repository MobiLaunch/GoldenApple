// LCode ▸ Settings: toolchains, the editor and the Simulator.
import QtQuick
import "../lib"
import "../lib/theme"
import "devices.js" as Devices

Sheet {
    id: sheet
    property var app
    panelWidth: 560

    readonly property var sizes: [11, 12, 13, 14, 15, 16, 18]


    Column {
        width: parent.width
        spacing: 12
        Text {
            text: "Settings"
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: 15; weight: Font.Bold }
        }

        SidebarSection { text: "Locations"; leftPadding: 0; topSpacing: 2 }
        Text {
            text: "Toolchains (leave a field empty to use the one on your PATH):"
            color: Theme.secondaryLabel
            font { family: Theme.fontUi; pixelSize: 12 }
        }
        Repeater {
            model: [
                { id: "swift", key: "swiftPath", placeholder: "/usr/bin/swift" },
                { id: "python", key: "pythonPath", placeholder: "/usr/bin/python3" },
                { id: "cargo", key: "cargoPath", placeholder: "~/.cargo/bin/cargo" },
                { id: "meson", key: "mesonPath", placeholder: "/usr/bin/meson" },
                { id: "goldengate", key: "qsPath", placeholder: "/usr/bin/qs" },
            ]
            delegate: Row {
                id: loc
                required property var modelData
                readonly property var info: sheet.app.toolchains[modelData.id] || ({ name: modelData.id, path: "", version: "", hint: "" })
                width: parent.width
                spacing: 8
                Column {
                    width: 120
                    anchors.verticalCenter: parent.verticalCenter
                    Text { text: loc.modelData.id === "goldengate" ? "Quickshell" : loc.info.name; color: Theme.label; font { family: Theme.fontUi; pixelSize: 13 } }
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: loc.info.path ? (loc.info.version || "Installed") : "Not installed"
                        color: loc.info.path ? Theme.secondaryLabel : "#ff453a"
                        font { family: Theme.fontUi; pixelSize: 10 }
                    }
                }
                TextField {
                    id: pathField
                    width: parent.width - 128
                    height: 28
                    placeholder: loc.info.path || loc.modelData.placeholder
                    text: sheet.app.settings[loc.modelData.key] || ""
                    onAccepted: sheet.app.saveSettings({ [loc.modelData.key]: text.trim() })
                    input.onActiveFocusChanged: if (!input.activeFocus && text.trim() !== (sheet.app.settings[loc.modelData.key] || ""))
                        sheet.app.saveSettings({ [loc.modelData.key]: text.trim() })
                }
            }
        }

        SidebarSection { text: "Text Editing"; leftPadding: 0; topSpacing: 6 }
        Row {
            spacing: 10
            Text { width: 140; anchors.verticalCenter: parent.verticalCenter; text: "Font Size"; color: Theme.label; font { family: Theme.fontUi; pixelSize: 13 } }
            PopUpButton {
                options: sheet.sizes.map((s) => s + " pt")
                current: Math.max(0, sheet.sizes.indexOf(sheet.app.settings.fontSize || 13))
                menuParent: sheet.parent
                onPicked: (i) => sheet.app.saveSettings({ fontSize: sheet.sizes[i] })
            }
        }
        Row {
            spacing: 10
            Text { width: 140; anchors.verticalCenter: parent.verticalCenter; text: "Tab Width"; color: Theme.label; font { family: Theme.fontUi; pixelSize: 13 } }
            PopUpButton {
                options: ["2 spaces", "4 spaces", "8 spaces"]
                current: Math.max(0, [2, 4, 8].indexOf(sheet.app.settings.tabWidth || 4))
                menuParent: sheet.parent
                onPicked: (i) => sheet.app.saveSettings({ tabWidth: [2, 4, 8][i] })
            }
        }
        Row {
            spacing: 10
            Text { width: 140; anchors.verticalCenter: parent.verticalCenter; text: "Show Minimap"; color: Theme.label; font { family: Theme.fontUi; pixelSize: 13 } }
            Switch {
                checked: sheet.app.settings.showMinimap !== false
                onToggled: (on) => sheet.app.saveSettings({ showMinimap: on })
            }
        }

        SidebarSection { text: "Simulator"; leftPadding: 0; topSpacing: 6 }
        Row {
            spacing: 10
            Text { width: 140; anchors.verticalCenter: parent.verticalCenter; text: "Default Device"; color: Theme.label; font { family: Theme.fontUi; pixelSize: 13 } }
            PopUpButton {
                options: Devices.DEVICES.map((d) => d.name)
                current: Math.max(0, Devices.DEVICES.findIndex((d) => d.id === sheet.app.settings.defaultSimulator))
                menuParent: sheet.parent
                onPicked: (i) => sheet.app.saveSettings({ defaultSimulator: Devices.DEVICES[i].id })
            }
        }
        Checkbox {
            width: parent.width
            text: "Show the Welcome window when LCode opens"
            checked: sheet.app.settings.showWelcome !== false
            onToggled: (on) => sheet.app.saveSettings({ showWelcome: on })
        }
        Row {
            anchors.right: parent.right
            Button { text: "Done"; prominent: true; onClicked: sheet.close() }
        }
    }
}
