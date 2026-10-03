// LCode ▸ Settings: the Swift toolchain, the editor and the Simulator.
import QtQuick
import "../lib"
import "../lib/theme"
import "devices.js" as Devices

Sheet {
    id: sheet
    property var app
    panelWidth: 560

    readonly property var sizes: [11, 12, 13, 14, 15, 16, 18]

    onShownChanged: if (shown) swiftField.text = app.settings.swiftPath || ""

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
            text: "Swift toolchain (leave empty to use swift on your PATH or $LCODE_SWIFT):"
            color: Theme.secondaryLabel
            font { family: Theme.fontUi; pixelSize: 12 }
        }
        Row {
            width: parent.width
            spacing: 8
            TextField {
                id: swiftField
                width: parent.width - apply.width - 8
                height: 30
                placeholder: "/usr/bin/swift"
                onAccepted: sheet.app.saveSettings({ swiftPath: text.trim() })
            }
            Button { id: apply; text: "Apply"; onClicked: sheet.app.saveSettings({ swiftPath: swiftField.text.trim() }) }
        }
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: sheet.app.swiftPath
                ? "Active: " + (sheet.app.swiftVersion || "unknown version") + "  —  " + sheet.app.swiftPath
                : "No Swift toolchain found. Install one from the AUR (yay -S swift-bin) or with swiftly."
            color: sheet.app.swiftPath ? Theme.secondaryLabel : "#ff453a"
            font { family: Theme.fontUi; pixelSize: 12 }
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
