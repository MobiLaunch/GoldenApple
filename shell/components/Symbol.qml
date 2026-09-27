// A glyph from shell/assets/symbols (generated from icons/source.mjs, or your
// own icons/custom/symbols overrides), tinted to any colour.
import QtQuick
import QtQuick.Effects

Item {
    id: root
    property string name
    property color color: "#ffffff"
    property real size: 18
    implicitWidth: size
    implicitHeight: size

    Image {
        id: img
        anchors.fill: parent
        source: Qt.resolvedUrl("../assets/symbols/" + root.name + ".svg")
        sourceSize: Qt.size(root.size * 2, root.size * 2)
        smooth: true
        visible: Qt.colorEqual(root.color, "#ffffff")
    }
    MultiEffect {
        anchors.fill: img
        source: img
        visible: !img.visible
        colorization: 1.0
        colorizationColor: root.color
    }
}
