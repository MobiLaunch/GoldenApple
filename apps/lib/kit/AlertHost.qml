// Shows the app's alerts (the Alert action) over its window.
import QtQuick
import "kit.js" as K
import "../theme"

Item {
    id: host
    property var app: null
    readonly property var kenv: K.findEnv(parent) || ({ dark: Theme.dark })
    readonly property bool dark: !!kenv.dark
    anchors.fill: parent
    visible: !!app && app.alertShown
    z: 900

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: host.dark ? 0.35 : 0.18
        MouseArea { anchors.fill: parent }
    }
    Rectangle {
        anchors.centerIn: parent
        width: 280
        height: column.implicitHeight + 36
        radius: 18
        color: host.dark ? "#f22c2c2e" : "#f7ffffff"
        border { width: 0.5; color: host.dark ? "#33ffffff" : "#1f000000" }
        Column {
            id: column
            x: 18; y: 18
            width: parent.width - 36
            spacing: 8
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: host.app ? host.app.alertTitle : ""
                color: K.color("label", host.kenv)
                font { family: Theme.fontUi; pixelSize: 14; weight: Font.Bold }
            }
            Text {
                width: parent.width
                visible: !!text
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: host.app ? host.app.alertMessage : ""
                color: K.color("secondaryLabel", host.kenv)
                font { family: Theme.fontUi; pixelSize: 12 }
            }
            Item { width: 1; height: 4 }
            Rectangle {
                width: parent.width
                height: 30
                radius: 15
                color: K.color("accent", host.kenv)
                Text { anchors.centerIn: parent; text: "OK"; color: "white"; font { family: Theme.fontUi; pixelSize: 13; weight: Font.DemiBold } }
                TapHandler { onTapped: host.app.alertShown = false }
            }
        }
    }
}
