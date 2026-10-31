// Progress from 0 to 1, or busy when there's no telling.
import QtQuick
import "kit.js" as K
import "../theme"

Box {
    id: root
    property real value: 0.4
    property bool indeterminate: false
    property string tint: ""
    contentWidth: 180
    contentHeight: 6
    readonly property color tintColor: c(tint || "accent", "#0a84ff")

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        clip: true
        color: root.dark ? "#3a3a3c" : "#e3e3e8"
        Rectangle {
            id: bar
            height: parent.height
            radius: height / 2
            color: root.tintColor
            width: root.indeterminate ? parent.width * 0.3 : parent.width * Math.max(0, Math.min(1, root.value))
            x: root.indeterminate ? sweep.x : 0
            Behavior on width { enabled: !root.indeterminate; NumberAnimation { duration: 175 } }
        }
        Item {
            id: sweep
            NumberAnimation on x {
                running: root.indeterminate && root.visible
                from: -root.innerWidth * 0.3; to: root.innerWidth
                duration: 955; loops: Animation.Infinite
            }
        }
    }
}
