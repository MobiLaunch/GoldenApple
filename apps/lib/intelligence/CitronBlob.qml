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
            const breath = 1 + 0.028 * Math.sin(t * 2) + 0.075 * e
            const colors = [
                [45, 167, 225], [67, 92, 219], [139, 79, 224],
                [214, 75, 190], [63, 207, 191], [228, 136, 153]
            ]
            const lobes = [
                [-0.080,-0.055,0.36,0.79,0.70,0.00],
                [ 0.073,-0.072,0.36,0.72,0.90,1.22],
                [ 0.086, 0.061,0.38,0.93,0.74,2.27],
                [-0.080, 0.084,0.35,0.78,1.03,3.11],
                [-0.028,-0.092,0.32,0.96,0.87,4.02],
                [ 0.038, 0.035,0.30,0.68,0.98,5.08]
            ]
            // Diffuse deep-indigo core darkens the identity without a panel.
            const undertone = ctx.createRadialGradient(w / 2, h / 2, 0,
                                                         w / 2, h / 2, size * 0.47)
            undertone.addColorStop(0, "rgba(19,17,63,0.20)")
            undertone.addColorStop(0.5, "rgba(35,27,83,0.10)")
            undertone.addColorStop(1, "rgba(30,20,75,0)")
            ctx.fillStyle = undertone
            ctx.fillRect(0, 0, w, h)
            for (let i = 0; i < lobes.length; i++) {
                const a = lobes[i], rgb = colors[i].join(",")
                const x = w * (0.5 + a[0] + 0.043 * Math.sin(t * a[3] + a[5]))
                const y = h * (0.5 + a[1] + 0.043 * Math.cos(t * a[4] + a[5]))
                const r = size * (a[2] + e * 0.023) * breath
                const alpha = 0.28 + e * 0.095
                ctx.save()
                ctx.translate(x, y)
                ctx.rotate(0.20 * Math.sin(t * 0.62 + a[5]))
                ctx.scale(1.14 + 0.07 * Math.sin(t + i), 0.98 + 0.06 * Math.cos(t * 0.75 + i))
                const grad = ctx.createRadialGradient(0, 0, 0, 0, 0, r)
                grad.addColorStop(0, "rgba(" + rgb + "," + alpha + ")")
                grad.addColorStop(0.28, "rgba(" + rgb + "," + (alpha * 0.78) + ")")
                grad.addColorStop(0.64, "rgba(" + rgb + "," + (alpha * 0.30) + ")")
                grad.addColorStop(1, "rgba(" + rgb + ",0)")
                ctx.fillStyle = grad
                ctx.beginPath()
                ctx.arc(0, 0, r, 0, 6.2831853)
                ctx.fill()
                ctx.restore()
            }
            const cx = w * (0.5 + 0.019 * Math.sin(t * 0.61))
            const cy = h * (0.5 + 0.019 * Math.cos(t * 0.79))
            const core = ctx.createRadialGradient(cx, cy, 0, cx, cy, size * 0.27)
            core.addColorStop(0, "rgba(157,126,223," + (0.09 + e * 0.045) + ")")
            core.addColorStop(0.54, "rgba(94,122,214,0.05)")
            core.addColorStop(1, "rgba(77,89,210,0)")
            ctx.fillStyle = core
            ctx.fillRect(0, 0, w, h)
            // The old lobes crossed the square Canvas bounds, creating a
            // visible rectangular crop. Fade alpha to ZERO at every edge.
            ctx.globalCompositeOperation = "destination-in"
            const feather = ctx.createRadialGradient(w / 2, h / 2, size * 0.28,
                                                      w / 2, h / 2, size * 0.49)
            feather.addColorStop(0, "rgba(255,255,255,1)")
            feather.addColorStop(0.38, "rgba(255,255,255,0.90)")
            feather.addColorStop(0.8, "rgba(255,255,255,0.30)")
            feather.addColorStop(1, "rgba(255,255,255,0)")
            ctx.fillStyle = feather
            ctx.fillRect(0, 0, w, h)
            ctx.globalCompositeOperation = "source-over"

        }
        Component.onCompleted: requestPaint()
    }
}
