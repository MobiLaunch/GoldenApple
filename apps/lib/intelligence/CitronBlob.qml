// Ambient voice identity: blended moving color fields, with no cutout,
// ring, capsule, hard outline or rectangular shadow. Receives levels only.
import QtQuick
import "../theme"

Item {
    id: blob
    objectName: "citronHazeField"
    implicitWidth: 360
    implicitHeight: 360
    property bool running: true
    property string mode: "listening"
    property real inputLevel: 0
    property real outputLevel: 0
    readonly property bool reduceMotion: Theme.reduceMotion
    property real phase: 0
    property real energy: 0
    readonly property real targetEnergy: mode === "speaking"
        ? 0.22 + Math.max(0, Math.min(1, outputLevel)) * 0.78
        : mode === "listening" ? 0.12 + Math.max(0, Math.min(1, inputLevel)) * 0.88
        : mode === "thinking" ? 0.26 : mode === "error" ? 0.12 : 0.08

    Timer {
        interval: 42
        repeat: true
        running: blob.running && blob.visible && !blob.reduceMotion
        onTriggered: {
            blob.phase = (blob.phase + (blob.mode === "speaking" ? 0.051 : 0.027)) % 6.2831853
            blob.energy += (blob.targetEnergy - blob.energy) *
                (blob.targetEnergy > blob.energy ? 0.29 : 0.11)
            field.requestPaint()
        }
    }
    onModeChanged: field.requestPaint()
    onInputLevelChanged: { if (reduceMotion) field.requestPaint() }
    onOutputLevelChanged: { if (reduceMotion) field.requestPaint() }
    onReduceMotionChanged: field.requestPaint()

    Canvas {
        id: field
        anchors.fill: parent
        renderTarget: Canvas.Image
        antialiasing: true
        onPaint: {
            const ctx = getContext("2d")
            const w = width, h = height, size = Math.min(w, h)
            ctx.clearRect(0, 0, w, h)
            const t = blob.reduceMotion ? 1.14 : blob.phase
            const e = blob.reduceMotion ? blob.targetEnergy : blob.energy
            const breath = 1 + 0.035 * Math.sin(t * 2) + 0.10 * e
            const colors = [
                [79, 217, 255], [76, 110, 255], [168, 104, 255],
                [255, 94, 204], [103, 252, 210], [255, 187, 133]
            ]
            const lobes = [
                [-0.17,-0.08,0.27,0.80,0.70,0.00],
                [ 0.18,-0.17,0.29,0.71,0.91,1.23],
                [ 0.19, 0.16,0.31,0.92,0.72,2.27],
                [-0.16, 0.19,0.27,0.77,1.09,3.31],
                [-0.06,-0.20,0.24,0.98,0.86,4.00],
                [ 0.07, 0.05,0.22,0.68,0.95,5.05]
            ]
            for (let i = 0; i < lobes.length; i++) {
                const a = lobes[i], rgb = colors[i].join(",")
                const x = w * (0.5 + a[0] + 0.09 * Math.sin(t * a[3] + a[5]))
                const y = h * (0.5 + a[1] + 0.09 * Math.cos(t * a[4] + a[5]))
                const r = size * (a[2] + e * 0.035) * breath
                const alpha = 0.47 + e * 0.13
                ctx.save()
                ctx.translate(x, y)
                ctx.rotate(0.34 * Math.sin(t * 0.7 + a[5]))
                ctx.scale(1.25 + 0.11 * Math.sin(t + i), 0.87 + 0.11 * Math.cos(t * 0.8 + i))
                const grad = ctx.createRadialGradient(0, 0, 0, 0, 0, r)
                grad.addColorStop(0, "rgba(" + rgb + "," + alpha + ")")
                grad.addColorStop(0.32, "rgba(" + rgb + "," + (alpha * 0.74) + ")")
                grad.addColorStop(0.66, "rgba(" + rgb + "," + (alpha * 0.27) + ")")
                grad.addColorStop(1, "rgba(" + rgb + ",0)")
                ctx.fillStyle = grad
                ctx.beginPath()
                ctx.arc(0, 0, r, 0, 6.2831853)
                ctx.fill()
                ctx.restore()
            }
            const cx = w * (0.5 + 0.025 * Math.sin(t * 0.61))
            const cy = h * (0.5 + 0.025 * Math.cos(t * 0.79))
            const core = ctx.createRadialGradient(cx, cy, 0, cx, cy, size * 0.22)
            core.addColorStop(0, "rgba(235,245,255," + (0.20 + e * 0.12) + ")")
            core.addColorStop(0.5, "rgba(210,220,255,0.08)")
            core.addColorStop(1, "rgba(220,230,255,0)")
            ctx.fillStyle = core
            ctx.fillRect(0, 0, w, h)
        }
        Component.onCompleted: requestPaint()
    }
}
