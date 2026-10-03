// The activity view: the glass capsule in the middle of the toolbar that says
// what LCode is doing ("Building Counter…", "Build Succeeded | Today at 10:42",
// "Running Counter on LPhone 16"), with progress and the issue counts.
import Quickshell
import QtQuick
import "../lib"
import "../lib/theme"

Item {
    id: view
    property var app
    signal issuesClicked()
    implicitHeight: 36

    Glass {
        anchors.fill: parent
        radius: height / 2
        role: "control"
    }

    Row {
        id: lead
        x: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        Image {
            anchors.verticalCenter: parent.verticalCenter
            width: 18; height: 18
            sourceSize: Qt.size(36, 36)
            source: Quickshell.iconPath("org.goldengate.LCode", true)
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: view.app.schemeName
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "|"
            color: Theme.tertiaryLabel
            font { family: Theme.fontUi; pixelSize: 13 }
        }
    }

    Text {
        x: lead.x + lead.width + 8
        width: badges.x - x - 10
        anchors.verticalCenter: parent.verticalCenter
        text: view.app.status
        elide: Text.ElideRight
        color: Theme.secondaryLabel
        font { family: Theme.fontUi; pixelSize: 13 }
    }

    Row {
        id: badges
        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
        spacing: 10
        Repeater {
            model: [
                { symbol: "warning", tone: "auto", color: "#ffb800", count: view.app.warningCount },
                { symbol: "xmark-circle", tone: "red", color: "transparent", count: view.app.errorCount },
            ]
            delegate: Row {
                required property var modelData
                visible: modelData.count > 0
                spacing: 3
                Symbol {
                    anchors.verticalCenter: parent.verticalCenter
                    name: modelData.symbol
                    tone: modelData.tone
                    color: modelData.color
                    size: 14
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.count
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: 12; weight: Font.DemiBold }
                }
                TapHandler { onTapped: view.issuesClicked() }
            }
        }
    }

    // Build progress: a hairline along the bottom of the capsule.
    Item {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 16; rightMargin: 16; bottomMargin: 2 }
        height: 3
        visible: view.app.progress !== -1
        ProgressBar {
            anchors.fill: parent
            value: Math.max(0, view.app.progress)
            indeterminate: view.app.progress === -2
        }
    }
}
