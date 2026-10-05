// Shared CitronOS progress bar.
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
        clip: true

        Rectangle {
            id: fill
            height: parent.height
            radius: height / 2
            color: Theme.accent
            width: root.indeterminate
                ? Math.max(24, parent.width * 0.28)
                : Math.max(0, Math.min(1, root.value)) * parent.width
            x: 0

            Behavior on width {
                enabled: !root.indeterminate && !Theme.reduceMotion
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            SequentialAnimation on x {
                id: sweep
                running: root.indeterminate && !Theme.reduceMotion
                loops: Animation.Infinite
                NumberAnimation {
                    from: -fill.width
                    to: Math.max(0, root.width)
                    duration: 1050
                    easing.type: Easing.InOutCubic
                }
                PauseAnimation { duration: 90 }
            }
        }
    }

    onIndeterminateChanged: {
        if (!indeterminate)
            fill.x = 0
        else if (Theme.reduceMotion)
            fill.x = Math.max(0, (root.width - fill.width) / 2)
    }
}
