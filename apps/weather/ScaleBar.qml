// A colour scale with a dot marking the value (air quality, UV index).
import QtQuick

Rectangle {
    id: bar
    property var stops: []       // [[position, color], ...]
    property real value: 0       // 0..1
    height: 5; radius: 2.5
    gradient: Gradient {
        id: grad
        orientation: Gradient.Horizontal
    }
    Component { id: stopComp; GradientStop {} }
    onStopsChanged: grad.stops = stops.map((s) => stopComp.createObject(bar, { position: s[0], color: s[1] }))
    Component.onCompleted: stopsChanged()
    Rectangle {
        width: 7; height: 7; radius: 3.5
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(0, Math.min(1, bar.value)) * (bar.width - width)
        color: "#ffffff"
        border { width: 1.5; color: "#59000000" }
    }
}
