// The Setup Assistant hello, drawn as a clean animated vector stroke.
// Liquid-glass optics now come from HyprGlass at compositor surfaces rather
// than a private per-widget shader.
import QtQuick
import QtQuick.Shapes

Item {
    id: hello
    property var source: null
    property Item backdropItem: null
    property real progress: 0
    readonly property real pathLength: 2729
    readonly property real strokeWidth: 30
    implicitWidth: 720
    implicitHeight: 340

    Shape {
        anchors.fill: parent
        layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software

        ShapePath {
            strokeColor: "#ffffff"
            strokeWidth: hello.strokeWidth
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            strokeStyle: hello.progress >= 0.999 ? ShapePath.SolidLine : ShapePath.DashLine
            dashPattern: [hello.pathLength / hello.strokeWidth + 2, hello.pathLength / hello.strokeWidth + 2]
            dashOffset: (1 - hello.progress) * (hello.pathLength / hello.strokeWidth + 2)
            PathSvg {
                path: "M 30 292 C 80 282, 140 205, 160 125 C 175 62, 158 30, 138 44 C 112 64, 112 180, 106 298 C 118 240, 142 205, 172 205 C 202 205, 212 232, 210 262 C 208 288, 218 300, 244 298 C 280 295, 316 262, 314 236 C 312 212, 286 210, 276 230 C 264 256, 276 300, 318 298 C 358 296, 398 220, 408 140 C 416 72, 398 40, 382 55 C 362 75, 362 200, 367 260 C 370 290, 388 300, 416 298 C 456 296, 496 220, 506 140 C 514 72, 496 40, 480 55 C 460 75, 460 200, 465 260 C 468 290, 486 300, 514 298 C 540 296, 560 250, 590 212 C 566 206, 548 250, 556 280 C 566 308, 618 306, 628 270 C 638 236, 620 204, 592 210 C 616 216, 648 222, 690 204"
            }
        }
    }

    // A faint under-stroke preserves the luminous macOS-style handwriting
    // without maintaining a second refraction implementation.
    Shape {
        anchors.fill: parent
        z: -1
        opacity: 0.18

        ShapePath {
            strokeColor: "#ffffff"
            strokeWidth: hello.strokeWidth + 10
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            strokeStyle: hello.progress >= 0.999 ? ShapePath.SolidLine : ShapePath.DashLine
            dashPattern: [hello.pathLength / (hello.strokeWidth + 10) + 2, hello.pathLength / (hello.strokeWidth + 10) + 2]
            dashOffset: (1 - hello.progress) * (hello.pathLength / (hello.strokeWidth + 10) + 2)
            PathSvg {
                path: "M 30 292 C 80 282, 140 205, 160 125 C 175 62, 158 30, 138 44 C 112 64, 112 180, 106 298 C 118 240, 142 205, 172 205 C 202 205, 212 232, 210 262 C 208 288, 218 300, 244 298 C 280 295, 316 262, 314 236 C 312 212, 286 210, 276 230 C 264 256, 276 300, 318 298 C 358 296, 398 220, 408 140 C 416 72, 398 40, 382 55 C 362 75, 362 200, 367 260 C 370 290, 388 300, 416 298 C 456 296, 496 220, 506 140 C 514 72, 496 40, 480 55 C 460 75, 460 200, 465 260 C 468 290, 486 300, 514 298 C 540 296, 560 250, 590 212 C 566 206, 548 250, 556 280 C 566 308, 618 306, 628 270 C 638 236, 620 204, 592 210 C 616 216, 648 222, 690 204"
            }
        }
    }
}
