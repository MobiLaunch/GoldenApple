// Liquid Glass for the Golden Gate apps, the same material as the shell's
// (shell/components/Glass.qml): tint, sheen, a lens band inside the edge and one
// hairline rim lit from the top left. `pressed` squashes and brightens it,
// `hovered` lifts it. Where it sits over a transparent window area, Hyprland
// blurs the desktop behind it.
import QtQuick
import QtQuick.Shapes
import "theme"

Item {
    id: root
    property real radius: 26
    property color tint: Theme.glassClear.tint
    property color rim: Theme.glassClear.rim
    property color rimLow: Theme.glassClear.rimLow
    property color shine: Theme.glassClear.shine
    property bool filled: false
    property bool pressed: false
    property bool hovered: false
    property real lens: Math.min(9, radius * 0.45)      // width of the lens band
    property color shadow: "transparent"                // a contact shadow 1px below (knobs, buttons)
    default property alias content: body.data

    readonly property real r: Math.min(radius, width / 2, height / 2)
    readonly property color shownTint: Theme.reduceTransparency ? Qt.rgba(tint.r, tint.g, tint.b, Math.max(tint.a, 0.94))
                                     : Theme.glassStyle === "tinted" ? Qt.rgba(tint.r, tint.g, tint.b, Math.max(tint.a, Math.min(0.86, tint.a + 0.32)))
                                     : tint

    // The press: a little smaller and brighter, springing back. A transform, so
    // users can still animate `scale` (Control Center's modules spring in).
    property real pressScale: pressed ? 0.955 : 1
    Behavior on pressScale { Spring { spring: Theme.snappy } }
    transform: Scale { origin.x: root.width / 2; origin.y: root.height / 2; xScale: root.pressScale; yScale: root.pressScale }

    Rectangle {
        visible: root.shadow.a > 0
        anchors { fill: parent; topMargin: 1; bottomMargin: -1 }
        radius: root.r
        color: root.shadow
    }
    Rectangle {
        id: bodyFill
        anchors.fill: parent
        radius: root.r
        color: root.filled ? "#ffffff" : root.shownTint
        Behavior on color { ColorAnimation { duration: 180 } }
    }
    Rectangle {
        anchors.fill: parent
        radius: root.r
        color: "#ffffff"
        opacity: root.pressed ? 0.12 : root.hovered ? 0.05 : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
    }
    // Sheen
    Rectangle {
        anchors.fill: parent
        radius: root.r
        visible: !root.filled
        opacity: 0.5
        gradient: Gradient {
            GradientStop { position: 0.0; color: root.shine }
            GradientStop { position: 0.42; color: "transparent" }
        }
    }
    // Lens band: light gathering toward the edge, brighter at the top. Four
    // nested rings of a quarter strength each, so it fades in steps too small to
    // read as an edge (one ring drew a hard inner outline, like a smaller copy).
    component LensRing: ShapePath {
        property real depth
        strokeColor: "transparent"
        fillRule: ShapePath.OddEvenFill
        fillGradient: LinearGradient {
            x1: 0; y1: 0; x2: root.width * 0.35; y2: root.height
            GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.045) }
            GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0.012) }
            GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.025) }
        }
        PathRectangle { x: 0; y: 0; width: root.width; height: root.height; radius: root.r }
        PathRectangle {
            x: depth; y: depth
            width: Math.max(0, root.width - 2 * depth); height: Math.max(0, root.height - 2 * depth)
            radius: Math.max(0, root.r - depth)
        }
    }
    Shape {
        anchors.fill: parent
        visible: !root.filled && root.lens > 1
        preferredRendererType: Shape.CurveRenderer
        LensRing { depth: root.lens }
        LensRing { depth: root.lens * 0.68 }
        LensRing { depth: root.lens * 0.42 }
        LensRing { depth: root.lens * 0.2 }
    }
    // Rim: one hairline ring, lit from the top left.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: "transparent"
            fillRule: ShapePath.OddEvenFill
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: root.width; y2: root.height
                GradientStop { position: 0; color: root.rim }
                GradientStop { position: 0.35; color: root.rimLow }
                GradientStop { position: 0.75; color: root.rimLow }
                GradientStop { position: 1; color: Qt.rgba(root.rim.r, root.rim.g, root.rim.b, root.rim.a * 0.55) }
            }
            PathRectangle { x: 0; y: 0; width: root.width; height: root.height; radius: root.r }
            PathRectangle { x: 1; y: 1; width: Math.max(0, root.width - 2); height: Math.max(0, root.height - 2); radius: Math.max(0, root.r - 1) }
        }
    }
    Item {
        id: body
        anchors.fill: parent
    }
}
