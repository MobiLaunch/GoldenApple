// Citron's orb: a living glass blob, as Siri's. Clouds of colour drift and
// swirl inside a liquid outline that breathes, swells with your voice and
// ripples while Citron speaks; a glass skin (rim light, a specular highlight,
// a soft bloom) sits over it.
//
//   level  0…1   the microphone (or speech) level, smoothed here
//   mode         "idle" | "connecting" | "listening" | "thinking" | "speaking" | "muted" | "error"
//
// Built from Qt's own pieces (Shape, MultiEffect), no custom shader: it runs
// wherever Qt Quick does. The software renderer has no effects: there the
// blob is filled with a gradient of the same colours instead of clouds.
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import "theme"

Item {
    id: orb
    property real level: 0
    property string mode: "idle"
    property bool running: visible
    implicitWidth: 120
    implicitHeight: 120

    readonly property real r: Math.min(width, height) / 2 * 0.86
    // Smoothed level: quick to rise, slow to fall, as a VU meter.
    property real energy: 0
    property real t: 0
    readonly property bool calm: Theme.reduceMotion
    readonly property bool busy: mode === "connecting" || mode === "thinking"
    readonly property bool effects: GraphicsInfo.api !== GraphicsInfo.Software

    // The hues per state: Siri's cyan, blue, violet and pink; grey muted.
    readonly property var hues: mode === "muted" ? ["#9aa3b5", "#6f7789", "#596173", "#848b9c"]
        : mode === "error" ? ["#ff8a7a", "#ff4d5e", "#c2306b", "#ff9f6b"]
        : ["#5ee7ff", "#3a7bff", "#a35cff", "#ff5fb4"]
    // How much the outline moves, and how fast everything turns.
    readonly property real wobble: calm ? 0.01
        : mode === "speaking" ? 0.035 + energy * 0.065
        : mode === "listening" ? 0.018 + energy * 0.075
        : busy ? 0.035 : mode === "muted" ? 0.008 : 0.016
    readonly property real pace: calm ? 0.15 : mode === "speaking" ? 1.6 : busy ? 2.2 : mode === "listening" ? 1.0 + energy : 0.45

    FrameAnimation {
        running: orb.running
        onTriggered: {
            const dt = Math.min(frameTime, 0.05)
            orb.t += dt * orb.pace
            const target = Math.max(0, Math.min(1, orb.level))
            orb.energy += (target - orb.energy) * (target > orb.energy ? 0.35 : 0.06)
            outline.update()
        }
    }

    // The outline: eight points around a circle, each on its own slow sine,
    // joined by a smooth closed curve (Catmull-Rom as cubic Béziers).
    QtObject {
        id: outline
        property string svg: ""
        function radiusAt(i) {
            const t = orb.t, k = i * 1.7
            const wave = Math.sin(t * 1.3 + k) * 0.6 + Math.sin(t * 2.1 - k * 1.3) * 0.4
            // Speaking adds a quicker ripple on top, as a voice would.
            const ripple = orb.mode === "speaking" ? Math.sin(t * 6.0 + k * 2.0) * 0.5 : 0
            return orb.r * (1 + orb.wobble * (wave + ripple))
        }
        function update() {
            const n = 8, cx = orb.width / 2, cy = orb.height / 2
            const pts = []
            for (let i = 0; i < n; i++) {
                const a = i / n * Math.PI * 2 + orb.t * 0.15
                const rr = radiusAt(i)
                pts.push([cx + Math.cos(a) * rr, cy + Math.sin(a) * rr])
            }
            let d = "M " + pts[0][0].toFixed(2) + " " + pts[0][1].toFixed(2)
            for (let i = 0; i < n; i++) {
                const p0 = pts[(i - 1 + n) % n], p1 = pts[i], p2 = pts[(i + 1) % n], p3 = pts[(i + 2) % n]
                const c1 = [p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6]
                const c2 = [p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6]
                d += " C " + c1[0].toFixed(2) + " " + c1[1].toFixed(2) + " " + c2[0].toFixed(2) + " " + c2[1].toFixed(2)
                     + " " + p2[0].toFixed(2) + " " + p2[1].toFixed(2)
            }
            svg = d + " Z"
        }
        Component.onCompleted: update()
    }

    // A soft bloom of the same colours behind the orb.
    Rectangle {
        anchors.centerIn: parent
        width: orb.r * 2.3; height: width; radius: width / 2
        opacity: orb.mode === "muted" ? 0.15 : 0.32 + orb.energy * 0.3
        gradient: Gradient {
            GradientStop { position: 0.0; color: orb.hues[0] }
            GradientStop { position: 1.0; color: orb.hues[2] }
        }
        layer.enabled: orb.effects
        layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 48 }
        Behavior on opacity { NumberAnimation { duration: 260 } }
        visible: orb.effects
    }

    // The silhouette, as a mask for the clouds.
    Shape {
        id: silhouette
        anchors.fill: parent
        visible: false
        layer.enabled: true
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            fillColor: "white"
            PathSvg { path: outline.svg }
        }
    }

    // Clouds of colour, drifting on Lissajous paths and blurred together.
    Item {
        id: clouds
        anchors.fill: parent
        visible: false
        // Thinking, the colours swirl round.
        rotation: orb.busy && !orb.calm ? orb.t * 40 : 0
        Rectangle { anchors.fill: parent; scale: 1.5; color: orb.hues[1]; Behavior on color { ColorAnimation { duration: 350 } } }
        Repeater {
            model: 4
            Rectangle {
                required property int index
                readonly property real phase: index * 1.57
                readonly property real reach: orb.r * (0.42 + 0.12 * Math.sin(orb.t * 0.7 + phase))
                width: orb.r * (index === 3 ? 0.9 : 1.15) * (1 + orb.energy * 0.25)
                height: width; radius: width / 2
                x: orb.width / 2 - width / 2 + Math.cos(orb.t * (0.8 + index * 0.23) + phase) * reach
                y: orb.height / 2 - height / 2 + Math.sin(orb.t * (1.1 + index * 0.17) + phase * 1.3) * reach
                color: orb.hues[index]
                opacity: 0.9
                Behavior on color { ColorAnimation { duration: 350 } }
            }
        }
        // A brighter core that brightens with the voice.
        Rectangle {
            anchors.centerIn: parent
            width: orb.r * (0.55 + orb.energy * 0.5); height: width; radius: width / 2
            color: "#ffffff"
            opacity: orb.mode === "muted" ? 0.08 : 0.22 + orb.energy * 0.35
        }
    }

    // Blurred, then cut to the outline: two passes, since MultiEffect drops
    // its mask when it also blurs.
    MultiEffect {
        id: blurred
        anchors.fill: parent
        source: clouds
        visible: false
        layer.enabled: true
        autoPaddingEnabled: false
        blurEnabled: orb.effects
        blur: 0.9
        blurMax: 40
    }
    MultiEffect {
        anchors.fill: parent
        visible: orb.effects
        source: blurred
        maskEnabled: true
        maskSource: silhouette
        maskThresholdMin: 0.5
        maskSpreadAtMin: 0.15
    }

    // Without effects: the blob in a gradient of its colours.
    Shape {
        anchors.fill: parent
        visible: !orb.effects
        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: orb.width * (0.5 + 0.12 * Math.cos(orb.t)); centerY: orb.height * (0.5 + 0.12 * Math.sin(orb.t * 1.3))
                centerRadius: orb.r * 1.1
                focalX: centerX; focalY: centerY
                GradientStop { position: 0.0; color: orb.hues[3] }
                GradientStop { position: 0.45; color: orb.hues[2] }
                GradientStop { position: 0.8; color: orb.hues[1] }
                GradientStop { position: 1.0; color: orb.hues[0] }
            }
            PathSvg { path: outline.svg }
        }
    }

    // Glass: a rim of light round the outline, brighter at the top, and a
    // specular highlight; both follow the outline as it moves.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: 1.4
            strokeColor: Qt.rgba(1, 1, 1, 0.55)
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: 0; y2: orb.height
                // Lit from above, deeper below, and a caustic of light where
                // the glass curves away at the bottom.
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.32) }
                GradientStop { position: 0.4; color: Qt.rgba(1, 1, 1, 0.0) }
                GradientStop { position: 0.82; color: Qt.rgba(0.02, 0.0, 0.12, 0.16) }
                GradientStop { position: 0.95; color: Qt.rgba(1, 1, 1, 0.12) }
            }
            PathSvg { path: outline.svg }
        }
    }
    Rectangle {
        x: orb.width / 2 - orb.r * 0.55
        y: orb.height / 2 - orb.r * 0.82
        width: orb.r * 0.8; height: orb.r * 0.36
        radius: height / 2
        rotation: -20
        opacity: 0.55
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.85) }
            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.0) }
        }
        layer.enabled: orb.effects
        layer.effect: MultiEffect { blurEnabled: true; blur: 0.35; blurMax: 12 }
    }
}
