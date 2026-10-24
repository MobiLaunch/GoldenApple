// Choose Your Look: Light, Dark or Auto, each shown as a little desktop,
// applied as soon as it's chosen.
import QtQuick
import "../lib"
import "../lib/theme"

StepFrame {
    id: step
    property string look: "light"
    signal chosen(string look)
    symbol: "contrast"
    title: "Choose Your Look"
    text: "Select an appearance. You can change it later in Control Center or Settings."

    component Preview: Item {
        id: pv
        property bool dark: false
        property bool split: false       // Auto: half light, half dark
        width: 150; height: 100
        Rectangle {
            anchors.fill: parent; radius: 10
            clip: true
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: pv.dark ? "#2a3a6e" : "#8fb6ea" }
                GradientStop { position: 1; color: pv.dark ? "#3b2358" : "#f3c28f" }
            }
            // Menu bar and a window, light or dark
            Repeater {
                model: pv.split ? [false, true] : [pv.dark]
                delegate: Item {
                    required property bool modelData
                    required property int index
                    x: pv.split ? index * pv.width / 2 : 0
                    width: pv.split ? pv.width / 2 : pv.width; height: pv.height
                    clip: true
                    Item {
                        x: pv.split ? -index * pv.width / 2 : 0
                        width: pv.width; height: pv.height
                        Rectangle { width: parent.width; height: 8; color: modelData ? "#b3202022" : "#b3ffffff" }
                        Rectangle {
                            x: 22; y: 20; width: 106; height: 62; radius: 6
                            color: modelData ? "#2c2c2e" : "#ffffff"
                            border { width: 0.5; color: "#33000000" }
                            Row {
                                x: 6; y: 6; spacing: 3
                                Repeater { model: ["#ff5f57", "#febc2e", "#28c840"]; delegate: Rectangle { required property string modelData; width: 5; height: 5; radius: 2.5; color: modelData } }
                            }
                            Rectangle { x: 6; y: 18; width: 26; height: 38; radius: 3; color: modelData ? "#3a3a3c" : "#ececf0" }
                            Repeater {
                                model: 3
                                delegate: Rectangle { required property int index; x: 38; y: 20 + index * 10; width: 58 - index * 12; height: 4; radius: 2; color: modelData ? "#636366" : "#d1d1d6" }
                            }
                        }
                    }
                }
            }
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 16
        spacing: 26
        Repeater {
            model: [{ v: "light", t: "Light" }, { v: "dark", t: "Dark" }, { v: "auto", t: "Auto" }]
            delegate: Column {
                required property var modelData
                spacing: 10
                Rectangle {
                    width: 158; height: 108; radius: 13
                    color: "transparent"
                    border { width: 3; color: step.look === modelData.v ? Theme.accent : "transparent" }
                    Preview {
                        anchors.centerIn: parent
                        dark: modelData.v === "dark"
                        split: modelData.v === "auto"
                    }
                    TapHandler { onTapped: { step.look = modelData.v; step.chosen(modelData.v) } }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.t
                    color: Theme.label
                    font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: step.look === modelData.v ? Font.DemiBold : Font.Normal }
                }
            }
        }
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 176
        width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
        visible: step.look === "auto"
        text: "Auto is light during the day and dark at night."
        color: Theme.secondaryLabel
        font { family: Theme.fontUi; pixelSize: Theme.fs(12) }
    }
}
