// A round Calculator key. Kinds: "digit" (dark grey), "function" (light grey),
// "operator" (orange; white with an orange glyph while it is the pending one).
import QtQuick
import QtQuick.Shapes
import "../lib/theme"

Item {
    id: key
    property string label
    property string kind: "digit"
    property bool selected: false
    property bool deleteGlyph: false
    property bool wide: false
    property bool compact: false        // Scientific and Programmer's smaller labels
    property bool lit: false            // a switch that's on (2nd, Rad)
    signal pressed()

    width: wide ? 100 : 47; height: 47
    opacity: enabled ? 1 : 0.35

    readonly property color base: kind === "operator" ? (selected ? "#ffffff" : "#ff9500")
                                : lit ? "#c9cbcd" : kind === "function" ? "#717577" : "#464a4c"
    readonly property color ink: (kind === "operator" && selected) ? "#ff9500" : lit ? "#1c1c1e" : "#ffffff"

    Rectangle {
        id: face
        anchors.fill: parent
        radius: height / 2
        color: key.base
        Behavior on color { ColorAnimation { duration: 140 } }
        // Liquid Glass: a light rim along the top, a faint darker edge below.
        border { width: 0.5; color: Qt.rgba(1, 1, 1, 0.10) }
        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1 }
            height: parent.height * 0.55
            radius: height / 2
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, key.kind === "operator" ? 0.22 : 0.10) }
                GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
            }
        }
        // Press: the key lights up and fades back, as on iOS and the Mac.
        Rectangle {
            id: flash
            anchors.fill: parent
            radius: height / 2
            color: "#ffffff"
            opacity: 0
        }
    }
    Text {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: key.kind === "operator" ? -1 : 0
        visible: !key.deleteGlyph
        text: key.label
        color: key.ink
        font {
            family: Theme.fontUi
            pixelSize: key.compact ? (key.label.length > 4 ? 12 : 15)
                     : key.kind === "operator" ? 33 : key.kind === "function" ? (key.label.length > 1 ? 20 : 24) : key.label.length > 1 ? 18 : 25
            weight: key.kind === "function" ? Font.Medium : Font.Light
        }
    }
    // ⌫, drawn: fonts rarely have a good one.
    Shape {
        anchors.centerIn: parent
        width: 24; height: 18
        visible: key.deleteGlyph
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: key.ink; strokeWidth: 1.9; fillColor: "transparent"
            joinStyle: ShapePath.RoundJoin; capStyle: ShapePath.RoundCap
            PathSvg { path: "M7.5 2 L21 2 Q23 2 23 4 L23 14 Q23 16 21 16 L7.5 16 L1.5 9 Z M11.5 5.5 L18 12.5 M18 5.5 L11.5 12.5" }
        }
    }
    TapHandler {
        enabled: key.enabled
        onTapped: { key.pressed(); flashAnim.restart() }
    }
    SequentialAnimation {
        id: flashAnim
        NumberAnimation { target: flash; property: "opacity"; to: 0.28; duration: 40 }
        NumberAnimation { target: flash; property: "opacity"; to: 0; duration: 280; easing.type: Easing.OutCubic }
    }
    function flashNow() { flashAnim.restart() }
}
