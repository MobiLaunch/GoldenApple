// A glyph from shell/assets/symbols (generated from icons/source.mjs, or your
// own icons/custom/symbols overrides).
//   tone: "white" | "accent" | "dark" | "gray"   pre-tinted files, no shader needed
//   color: any other colour; tinted with MultiEffect on the GPU renderer
import QtQuick
import QtQuick.Effects

Item {
    id: root
    property string name
    property string tone: "white"
    property color color: "transparent"
    property real size: 18
    implicitWidth: size
    implicitHeight: size

    readonly property bool customColor: color.a > 0 && GraphicsInfo.api !== GraphicsInfo.Software

    Image {
        id: img
        anchors.fill: parent
        source: Qt.resolvedUrl("../assets/symbols/" + root.name + (root.tone === "white" ? "" : "@" + root.tone) + ".svg")
        sourceSize: Qt.size(root.size * 2, root.size * 2)
        smooth: true
        visible: !root.customColor
    }
    MultiEffect {
        anchors.fill: img
        source: img
        visible: root.customColor
        colorization: 1.0
        colorizationColor: root.color
    }
}
