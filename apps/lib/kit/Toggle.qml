// On or off, as a switch or a checkbox, with a label.
import QtQuick
import "kit.js" as K
import "../theme"

Box {
    id: root
    property string label: "Toggle"
    property bool value: false
    property string toggleStyle: "switch"     // switch | checkbox
    property string tint: ""
    signal edited(bool value)
    // What it shows: follows value, and flips at once when clicked (the
    // app's variable catches up through `edited`).
    property bool on: value
    onValueChanged: on = value
    readonly property color tintColor: c(tint || "accent", "#0a84ff")
    readonly property bool sw: toggleStyle !== "checkbox"
    contentWidth: labelText.implicitWidth + (labelText.text ? 10 : 0) + control.width
    contentHeight: Math.max(labelText.implicitHeight, control.height)

    function flip() { on = !on; edited(on) }

    Text {
        id: labelText
        x: root.sw ? 0 : control.width + 8
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, root.innerWidth - control.width - 10)
        elide: Text.ElideRight
        text: root.label
        color: root.foregroundColor
        font { family: K.fontFamily("", root.kenv, Theme.fontUi); pixelSize: 13 }
    }
    Item {
        id: control
        x: root.sw ? root.innerWidth - width : 0
        anchors.verticalCenter: parent.verticalCenter
        width: root.sw ? 38 : 16
        height: root.sw ? 22 : 16
        Rectangle {
            anchors.fill: parent
            radius: root.sw ? height / 2 : 4
            color: root.on ? root.tintColor : (root.sw ? (root.dark ? "#39393d" : "#e3e3e8") : (root.dark ? "#26ffffff" : "#ffffff"))
            border { width: !root.sw && !root.on ? 1 : 0; color: root.dark ? "#40ffffff" : "#33000000" }
            Behavior on color { ColorAnimation { duration: Theme.reduceMotion ? 1 : 150 } }
        }
        Rectangle {
            visible: root.sw
            width: 18; height: 18; radius: 9
            y: 2
            x: root.on ? parent.width - width - 2 : 2
            color: "white"
            border { width: 0.5; color: "#1f000000" }
            Behavior on x { NumberAnimation { duration: Theme.reduceMotion ? 1 : 160; easing.type: Easing.OutCubic } }
        }
        Text {
            visible: !root.sw && root.on
            anchors.centerIn: parent
            text: "✓"
            color: K.onColor(String(root.tintColor))
            font { pixelSize: 12; weight: Font.Bold }
        }
    }
    TapHandler { onTapped: root.flip() }
}
