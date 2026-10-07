// Where you are on the map: Maps' blue dot in a white ring, a soft pulse, and
// a pale circle as wide as the location's uncertainty.
import QtQuick
import "../lib/theme"

Item {
    id: dot
    property Item view
    property real lat: 0
    property real lon: 0
    property real accuracy: 0          // metres
    readonly property point at: view ? view.toScreen(lat, lon) : Qt.point(0, 0)
    // The accuracy circle's radius in pixels: a latitude step that many metres.
    readonly property real spread: view ? Math.abs(view.toScreen(lat + accuracy / 111320, lon).y - at.y) : 0
    x: at.x; y: at.y
    width: 0; height: 0

    Rectangle {
        anchors.centerIn: parent
        visible: dot.spread > 14
        width: dot.spread * 2; height: width; radius: width / 2
        color: Qt.rgba(0.04, 0.52, 1, 0.12)
        border { width: 1; color: Qt.rgba(0.04, 0.52, 1, 0.3) }
    }
    Rectangle {
        id: pulse
        anchors.centerIn: parent
        width: 22; height: 22; radius: 11
        color: Qt.rgba(0.04, 0.52, 1, 0.35)
        SequentialAnimation on scale {
            running: !Theme.reduceMotion && dot.visible
            loops: Animation.Infinite
            NumberAnimation { from: 1; to: 2.2; duration: 1600; easing.type: Easing.OutCubic }
            PauseAnimation { duration: 400 }
        }
        SequentialAnimation on opacity {
            running: !Theme.reduceMotion && dot.visible
            loops: Animation.Infinite
            NumberAnimation { from: 0.9; to: 0; duration: 1600; easing.type: Easing.OutCubic }
            PauseAnimation { duration: 400 }
        }
    }
    Rectangle {
        anchors.centerIn: parent
        width: 20; height: 20; radius: 10
        color: "#ffffff"
        Rectangle { anchors.centerIn: parent; width: 14; height: 14; radius: 7; color: "#0a84ff" }
    }
}
