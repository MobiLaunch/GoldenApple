import QtQuick
import "../lib"
import "../lib/theme"

Item {
    id: root
    property string symbol
    property string tooltip
    property bool selected: false
    property bool circular: false
    signal clicked()
    implicitWidth: 32
    implicitHeight: 32
    opacity: enabled ? 1 : 0.35
    Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 1 : 140 } }
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: tooltip
    Accessible.onPressAction: if (enabled) clicked()

    Rectangle {
        anchors.fill: parent
        radius: root.circular ? width / 2 : 9
        color: Theme.dark ? "#ffffff" : "#000000"
        opacity: root.selected ? (Theme.dark ? 0.16 : 0.08)
            : area.pressed ? (Theme.dark ? 0.14 : 0.09)
            : area.containsMouse ? (Theme.dark ? 0.09 : 0.055) : 0
        Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 1 : 90 } }
    }

    // A little hop to say something happened (a favorite added, a download begun).
    function bump() { if (!Theme.reduceMotion) hop.restart() }
    property real hopScale: 1
    SequentialAnimation {
        id: hop
        NumberAnimation { target: root; property: "hopScale"; to: 1.3; duration: 130; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "hopScale"; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
    }

    Symbol {
        anchors.centerIn: parent
        name: root.symbol
        size: 16
        tone: "auto"
        scale: (area.pressed && !Theme.reduceMotion ? 0.90 : 1) * root.hopScale
        Behavior on scale { enabled: !hop.running; NumberAnimation { duration: Theme.reduceMotion ? 1 : 80; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled
        onClicked: { root.forceActiveFocus(); root.clicked() }
    }

    Keys.onSpacePressed: if (enabled) clicked()
    Keys.onReturnPressed: if (enabled) clicked()
    Keys.onEnterPressed: if (enabled) clicked()

    Rectangle {
        visible: opacity > 0.01
        z: 10
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height + 7
        width: tipLabel.implicitWidth + 16
        height: 24
        radius: 7
        color: Theme.dark ? "#ee303034" : "#eef4f4f6"
        border { width: 0.5; color: Theme.separator }
        opacity: tip.visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 1 : 120 } }

        Text {
            id: tipLabel
            anchors.centerIn: parent
            text: root.tooltip
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: 11 }
        }
    }
    Timer {
        id: tip
        property bool visible: false
        interval: 550
        onTriggered: visible = area.containsMouse && !area.pressed
    }
    Connections {
        target: area
        function onContainsMouseChanged() {
            tip.visible = false
            if (area.containsMouse) tip.restart()
            else tip.stop()
        }
    }
}
