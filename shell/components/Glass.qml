// Liquid Glass surface. The blur itself comes from the compositor
// (Hyprland `layerrule = blur` + `ignorealpha` on the gg-* namespaces);
// this item paints the tint, the specular rim and the top-left light catch
// on top of it, matching the recipe in prototype/css/shell.css.
import QtQuick
import "../theme"

Item {
    id: root
    property real radius: 26
    property color tint: Theme.glassClear.tint
    property color rim: Theme.glassClear.rim
    property color shine: Theme.glassClear.shine
    // "on" state for toggles: an opaque white body, like an active control.
    property bool filled: false
    default property alias content: body.data

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.filled ? "#ffffff" : root.tint
        Behavior on color { ColorAnimation { duration: 180 } }
    }
    // Light catch: bright at the top edge, fading out by the middle.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        visible: !root.filled
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.shine }
            GradientStop { position: 0.45; color: "transparent" }
        }
        opacity: 0.55
    }
    // Rim: a bright hairline, stronger on top than on the bottom.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        border.width: 1
        border.color: root.rim
        opacity: 0.55
    }
    Rectangle {
        anchors { fill: parent; topMargin: parent.height * 0.5 }
        radius: root.radius
        color: "transparent"
        border.width: 1
        border.color: Theme.glassClear.rimLow
    }
    Item {
        id: body
        anchors.fill: parent
    }
}
