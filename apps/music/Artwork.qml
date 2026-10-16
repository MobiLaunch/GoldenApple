// Album art with rounded corners in any renderer: the corners are painted over
// in the colour behind (maskColor) instead of needing a shader to clip. A grey
// tile with a note stands in while there's no art.
import QtQuick
import QtQuick.Shapes
import "../lib"
import "../lib/theme"

Item {
    id: art
    property url source
    property real radius: 6
    property color maskColor: Theme.contentBg
    property bool round: false           // artists: a circle
    readonly property real r: round ? width / 2 : radius

    Rectangle {
        anchors.fill: parent
        radius: art.r
        visible: img.status !== Image.Ready
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.dark ? "#4a4a4e" : "#e3e3e8" }
            GradientStop { position: 1; color: Theme.dark ? "#3a3a3c" : "#d1d1d6" }
        }
        Symbol {
            anchors.centerIn: parent
            name: art.round ? "person" : "music"; tone: "gray"
            size: Math.max(12, parent.width * 0.36)
        }
    }
    Image {
        id: img
        anchors.fill: parent
        source: art.source
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(Math.ceil(art.width * 2), Math.ceil(art.height * 2))
        asynchronous: true
        smooth: true; mipmap: true
        visible: status === Image.Ready
    }
    Shape {
        anchors.fill: parent
        visible: art.r > 0 && img.visible
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: art.maskColor
            strokeColor: "transparent"
            fillRule: ShapePath.OddEvenFill
            PathRectangle { x: -1; y: -1; width: art.width + 2; height: art.height + 2 }
            PathRectangle { x: 0; y: 0; width: art.width; height: art.height; radius: art.r }
        }
    }
    Rectangle {
        anchors.fill: parent
        radius: art.r
        color: "transparent"
        border { width: 0.5; color: Theme.dark ? "#1affffff" : "#14000000" }
    }
}
