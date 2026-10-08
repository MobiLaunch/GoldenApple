// An image clipped to a rounded rectangle (the path is filled with the image's
// texture), with a hairline edge and a grey tile while loading. Qt's software
// renderer can't fill a path with a texture (it drew a blank white tile), so
// without a GPU the picture is drawn as it is, square cornered.
import QtQuick
import QtQuick.Shapes
import "theme"

Item {
    id: ri
    property url source
    property real radius: 8
    property int fillMode: Image.PreserveAspectCrop
    readonly property alias status: img.status
    readonly property bool shapes: GraphicsInfo.api !== GraphicsInfo.Software

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
        clip: true
        smooth: true; mipmap: true
    }
    // The image as drawn (fill mode applied), as a texture the size of this item.
    ShaderEffectSource {
        id: tex
        width: ri.width; height: ri.height
        sourceItem: ri.shapes ? img : null
        hideSource: ri.shapes
        visible: false
    }
    Shape {
        anchors.fill: parent
        visible: ri.shapes && img.status === Image.Ready
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
