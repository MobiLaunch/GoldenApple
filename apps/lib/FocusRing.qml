// Consistent keyboard focus without changing the control's layout.
import QtQuick
import "theme"
Rectangle {
    anchors { fill: parent; margins: -3 }
    radius: Math.min(width, height) / 2
    color: "transparent"
    border { width: 2; color: Theme.accent }
    // Gentle two-tone focus halo without a GPU blur or a layout change.
    Rectangle {
        anchors { fill: parent; margins: -2 }
        radius: parent.radius + 2
        color: "transparent"
        border { width: 2; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, Theme.dark ? 0.23 : 0.16) }
    }
    visible: opacity > 0
    opacity: parent.activeFocus && parent.enabled ? 1 : 0
    scale: parent.activeFocus && parent.enabled && !Theme.reduceMotion ? 1 : 0.985
    Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 1 : 110; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: Theme.reduceMotion ? 1 : 120; easing.type: Easing.OutCubic } }
    z: 10
}
