// An image clipped to a rounded rectangle in any renderer (the path is filled
// with the image's texture), with a hairline edge and a grey tile while loading.
import QtQuick
import QtQuick.Shapes
import "theme"

Item {
    id: ri
    property url source
    property real radius: 8
    property int fillMode: Image.PreserveAspectCrop
    readonly property alias status: img.status

    Rectangle {
        anchors.fill: parent
        radius: ri.radius
        visible: img.status !== Image.Ready
        color: Theme.dark ? "#3a3a3c" : "#e3e3e8"
    }
    Image {
        id: img
        width: ri.width; height: ri.height
        source: ri.source
        fillMode: ri.fillMode
        sourceSize: Qt.size(Math.ceil(ri.width * 2), Math.ceil(ri.height * 2))
        asynchronous: true
        smooth: true; mipmap: true
    }
    // The image as drawn (fill mode applied), as a texture the size of this item.
    ShaderEffectSource {
        id: tex
        width: ri.width; height: ri.height
        sourceItem: img
        hideSource: true
        visible: false
    }
    Shape {
        anchors.fill: parent
        visible: img.status === Image.Ready
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"
            fillItem: tex
            PathRectangle { x: 0; y: 0; width: ri.width; height: ri.height; radius: ri.radius }
        }
    }
    Rectangle {
        anchors.fill: parent
        radius: ri.radius
        color: "transparent"
        border { width: 0.5; color: Theme.dark ? "#1affffff" : "#1a000000" }
    }
}
