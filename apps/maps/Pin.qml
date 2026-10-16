// A place on the map: a round marker in the place's colour with a small
// tail, as Maps draws them, or a plain dot for a route's start.
import QtQuick
import "../lib"
import "../lib/theme"

Item {
    id: pin
    property var view
    property real lat
    property real lon
    property color color: "#ff3b30"
    property string symbol: "pin"
    property string label: ""
    property bool dot: false
    signal clicked()
    readonly property point p: { void view.lat; void view.lon; void view.zoom; void view.width; return view.toScreen(lat, lon) }
    x: p.x; y: p.y
    z: 5

    // Start: a white dot with a coloured centre.
    Rectangle {
        visible: pin.dot
        x: -9; y: -9; width: 18; height: 18; radius: 9
        color: "#ffffff"
        border { width: 0.5; color: "#40000000" }
        Rectangle { anchors.centerIn: parent; width: 10; height: 10; radius: 5; color: pin.color }
    }
    // Marker: circle and tail, bottom at the point.
    Item {
        visible: !pin.dot
        x: -16; y: -40; width: 32; height: 40
        Rectangle {
            x: 13; y: 26; width: 6; height: 12; radius: 3
            color: pin.color
        }
        Rectangle {
            width: 32; height: 32; radius: 16
            color: pin.color
            border { width: 2; color: "#ffffff" }
            Symbol { anchors.centerIn: parent; name: pin.symbol; tone: "white"; size: 16 }
        }
        TapHandler { onTapped: pin.clicked() }
    }
    Text {
        visible: !!pin.label
        anchors.horizontalCenter: parent.horizontalCenter
        y: pin.dot ? 10 : 4
        text: pin.label
        color: "#1d1d1f"
        style: Text.Outline; styleColor: "#e6ffffff"
        font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: Font.DemiBold }
    }
}
