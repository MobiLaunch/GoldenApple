// Liquid Glass surface. HyprGlass owns compositor backdrop blur/refraction for
// the whitelisted gg-* layer namespaces; this item paints only the shared
// material tint, sheen, lens edge, rim and interaction chrome:
//
//   body      the tint (white when `filled`, an active control)
//   sheen     light across the top, fading by the middle
//   lens      a lighter band just inside the edge: the glass's thickness,
//             complementing HyprGlass' compositor-level refraction
//   rim       a hairline ring lit from the top left, dimmer along the sides,
//             with a softer catch on the far edge
//
// `pressed` squashes and brightens it slightly (the Liquid Glass press), and
// `hovered` lifts it a little. Rings are Shapes with even-odd fills, so there's
// exactly one outline whatever the size.
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import "../theme"

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
    default property alias content: body.data

    readonly property real r: Math.min(radius, width / 2, height / 2)
    // Settings › Appearance › Liquid Glass (clear or tinted), and Accessibility ›
    // Reduce transparency (nearly opaque).
    readonly property color shownTint: Prefs.reduceTransparency
        ? Qt.rgba(tint.r, tint.g, tint.b, Math.max(tint.a, 0.94))
        : Prefs.glass === "tinted"
            ? Qt.rgba(tint.r, tint.g, tint.b, Math.max(tint.a, 0.72))
            : Qt.rgba(tint.r, tint.g, tint.b, Math.max(tint.a, Theme.dark ? 0.38 : 0.42))

    // The press: a little smaller and brighter, springing back. A transform, so
    // users can still animate `scale` (Control Center's modules spring in).
    property real pressScale: pressed ? 0.955 : 1
    Behavior on pressScale { Spring { spring: Theme.snappy } }
    transform: Scale { origin.x: root.width / 2; origin.y: root.height / 2; xScale: root.pressScale; yScale: root.pressScale }

    // Ambient elevation: broad and soft. Avoid the hard button-shaped drop
    // shadow that made controls look outlined rather than suspended in glass.
    Rectangle {
        id: shadowShape
        anchors.fill: parent; radius: root.r; color: "#ffffff"; visible: false
    }
    MultiEffect {
        anchors.fill: shadowShape
        source: shadowShape
        autoPaddingEnabled: true
        shadowEnabled: true
        shadowColor: "#80000000"
        shadowOpacity: root.pressed ? 0.14 : root.hovered ? 0.27 : 0.20
        shadowBlur: 1.0
        shadowVerticalOffset: root.pressed ? 2 : root.hovered ? 7 : 5
        shadowHorizontalOffset: 0
    }
    Rectangle {
        id: bodyFill
        anchors.fill: parent
        radius: root.r
        color: root.filled ? (Theme.dark ? "#e6ffffff" : "#f2ffffff") : root.shownTint
        Behavior on color { ColorAnimation { duration: 180 } }
    }
    Rectangle {
        anchors.fill: parent
        radius: root.r
        color: "#ffffff"
        opacity: root.pressed ? 0.16 : root.hovered ? 0.08 : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
    }
    // Sheen
    Rectangle {
        anchors.fill: parent
        radius: root.r
        visible: !root.filled
        opacity: 0.72
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
            GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.10) }
            GradientStop { position: 0.55; color: Qt.rgba(1, 1, 1, 0.025) }
            GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0.055) }
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
