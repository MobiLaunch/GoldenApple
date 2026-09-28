// Consistent keyboard focus without changing the control's layout.
import QtQuick
import "theme"
Rectangle {
    anchors { fill: parent; margins: -3 }
    radius: Math.min(width, height) / 2
    color: "transparent"
    border { width: 2; color: Theme.accent }
    visible: parent.activeFocus && parent.enabled
    z: 10
}
