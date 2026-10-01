// Shared Golden Gate progress bar.
import QtQuick
import "theme"

Item {
    id: root
    property real value: 0
    property bool indeterminate: false
    implicitWidth: 240
    implicitHeight: 8

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Theme.dark ? "#24ffffff" : "#14000000"

        Rectangle {
            id: fill
            height: parent.height
            radius: height / 2
            color: Theme.accent
            width: root.indeterminate ? parent.width * 0.28 : Math.max(0, Math.min(1, root.value)) * parent.width
            x: root.indeterminate ? sweep.value * Math.max(0, parent.width - width) : 0
            Behavior on width {
                enabled: !root.indeterminate && !Theme.reduceMotion
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
        }
    }

    NumberAnimation {
        id: sweep
        target: fill
        property: "x"
        from: 0
        to: Math.max(0, root.width - fill.width)
        duration: Theme.reduceMotion ? 1 : 900
        loops: Animation.Infinite
        running: root.indeterminate && !Theme.reduceMotion
        easing.type: Easing.InOutSine
    }
}
