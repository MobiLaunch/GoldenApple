// Setup Assistant's backdrop: deep blue with slow, soft light drifting through
// it in the Golden Gate colours. It is what the Liquid Glass bends, so it has
// colour everywhere and no hard edges. Painted as large radial gradients;
// the drift stops under the software renderer (VMs), where it would cost.
import QtQuick
import QtQuick.Shapes

Item {
    id: bg
    property bool moving: true

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: "#101a4a" }
            GradientStop { position: 0.55; color: "#1b1446" }
            GradientStop { position: 1; color: "#2a0f35" }
        }
    }

    // [colour, x, y, radius (in screen heights), drift x, drift y, seconds]
    readonly property var lights: [
        ["#ffb347", 0.18, 0.78, 0.62, 0.10, -0.08, 23],
        ["#ff5f7a", 0.72, 0.86, 0.55, -0.12, -0.06, 29],
        ["#b35cff", 0.84, 0.22, 0.60, -0.08, 0.10, 31],
        ["#2f8dff", 0.30, 0.18, 0.66, 0.12, 0.06, 27],
        ["#22d3c5", 0.52, 0.52, 0.42, -0.10, 0.08, 35],
        ["#ffd86b", 0.95, 0.60, 0.35, -0.14, 0.04, 21],
    ]
    Repeater {
        model: bg.lights
        delegate: Shape {
            id: light
            required property var modelData
            readonly property real r: bg.height * modelData[3]
            readonly property color base: modelData[0]
            property real dx: 0
            property real dy: 0
            x: bg.width * modelData[1] + dx * bg.width - r
            y: bg.height * modelData[2] + dy * bg.height - r
            width: r * 2; height: r * 2
            opacity: 0.85
            ShapePath {
                strokeColor: "transparent"
                fillGradient: RadialGradient {
                    centerX: light.r; centerY: light.r; centerRadius: light.r
                    focalX: light.r; focalY: light.r
                    GradientStop { position: 0; color: light.base }
                    GradientStop { position: 0.45; color: Qt.rgba(light.base.r, light.base.g, light.base.b, 0.45) }
                    GradientStop { position: 1; color: Qt.rgba(light.base.r, light.base.g, light.base.b, 0) }
                }
                PathRectangle { x: 0; y: 0; width: light.width; height: light.height }
            }
            SequentialAnimation on dx {
                running: bg.moving; loops: Animation.Infinite
                NumberAnimation { to: light.modelData[4]; duration: light.modelData[6] * 500; easing.type: Easing.InOutSine }
                NumberAnimation { to: -light.modelData[4] * 0.6; duration: light.modelData[6] * 1000; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0; duration: light.modelData[6] * 500; easing.type: Easing.InOutSine }
            }
            SequentialAnimation on dy {
                running: bg.moving; loops: Animation.Infinite
                NumberAnimation { to: light.modelData[5]; duration: light.modelData[6] * 700; easing.type: Easing.InOutSine }
                NumberAnimation { to: -light.modelData[5] * 0.7; duration: light.modelData[6] * 900; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0; duration: light.modelData[6] * 400; easing.type: Easing.InOutSine }
            }
        }
    }
}
