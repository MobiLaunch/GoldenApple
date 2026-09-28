// The hello: written out in one stroke, then held, in Liquid Glass. The stroke
// is drawn into a mask and glass-stroke.frag bends the backdrop through it.
// Without shaders the stroke is drawn in white.
import QtQuick
import QtQuick.Shapes

Item {
    id: hello
    property var source                 // ShaderEffectSource of the backdrop
    property Item backdropItem
    property real progress: 0           // how much is written, 0..1
    readonly property real pathLength: 2729
    readonly property real strokeWidth: 30
    readonly property bool shaders: GraphicsInfo.api !== GraphicsInfo.Software && GraphicsInfo.api !== GraphicsInfo.Unknown
    implicitWidth: 720; implicitHeight: 340

    Shape {
        id: stroke
        anchors.fill: parent
        visible: !hello.shaders
        ShapePath {
            strokeColor: "#ffffff"
            strokeWidth: hello.strokeWidth
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            strokeStyle: hello.progress >= 0.999 ? ShapePath.SolidLine : ShapePath.DashLine
            // A dash as long as the path, slid along it: the writing.
            dashPattern: [hello.pathLength / hello.strokeWidth + 2, hello.pathLength / hello.strokeWidth + 2]
            dashOffset: (1 - hello.progress) * (hello.pathLength / hello.strokeWidth + 2)
            PathSvg { path: "M 30 292 C 80 282, 140 205, 160 125 C 175 62, 158 30, 138 44 C 112 64, 112 180, 106 298 C 118 240, 142 205, 172 205 C 202 205, 212 232, 210 262 C 208 288, 218 300, 244 298 C 280 295, 316 262, 314 236 C 312 212, 286 210, 276 230 C 264 256, 276 300, 318 298 C 358 296, 398 220, 408 140 C 416 72, 398 40, 382 55 C 362 75, 362 200, 367 260 C 370 290, 388 300, 416 298 C 456 296, 496 220, 506 140 C 514 72, 496 40, 480 55 C 460 75, 460 200, 465 260 C 468 290, 486 300, 514 298 C 540 296, 560 250, 590 212 C 566 206, 548 250, 556 280 C 566 308, 618 306, 628 270 C 638 236, 620 204, 592 210 C 616 216, 648 222, 690 204" }
        }
    }
    ShaderEffectSource {
        id: mask
        sourceItem: stroke
        hideSource: hello.shaders
        live: true
        smooth: true
        samples: 4
        textureSize: Qt.size(hello.width * 1.5, hello.height * 1.5)
    }
    ShaderEffect {
        id: effect
        anchors.fill: parent
        visible: hello.shaders && !!hello.source
        property var backdrop: hello.source
        property var mask: mask
        property size screenSize: Qt.size(hello.backdropItem ? hello.backdropItem.width : 1, hello.backdropItem ? hello.backdropItem.height : 1)
        property vector4d itemRect: Qt.vector4d(0, 0, 1, 1)
        property real bevel: 13 * hello.scale
        property real strength: 38
        property point lightDir: Qt.point(-0.5, -0.86)
        property vector4d tint: Qt.vector4d(0.03, 0.03, 0.04, 0.04)
        fragmentShader: Qt.resolvedUrl("shaders/glass-stroke.frag.qsb")
        function place() {
            if (!hello.backdropItem) return
            const p = hello.mapToItem(hello.backdropItem, 0, 0)
            itemRect = Qt.vector4d(p.x, p.y, hello.width * hello.scale, hello.height * hello.scale)
        }
        FrameAnimation { running: effect.visible; onTriggered: effect.place() }
    }
    // White stroke under the glass for a soft light behind it, as the Mac's
    // hello has a faint glow.
    Shape {
        anchors.fill: parent
        visible: hello.shaders
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
            PathSvg { path: "M 30 292 C 80 282, 140 205, 160 125 C 175 62, 158 30, 138 44 C 112 64, 112 180, 106 298 C 118 240, 142 205, 172 205 C 202 205, 212 232, 210 262 C 208 288, 218 300, 244 298 C 280 295, 316 262, 314 236 C 312 212, 286 210, 276 230 C 264 256, 276 300, 318 298 C 358 296, 398 220, 408 140 C 416 72, 398 40, 382 55 C 362 75, 362 200, 367 260 C 370 290, 388 300, 416 298 C 456 296, 496 220, 506 140 C 514 72, 496 40, 480 55 C 460 75, 460 200, 465 260 C 468 290, 486 300, 514 298 C 540 296, 560 250, 590 212 C 566 206, 548 250, 556 280 C 566 308, 618 306, 628 270 C 638 236, 620 204, 592 210 C 616 216, 648 222, 690 204" }
        }
    }
}
