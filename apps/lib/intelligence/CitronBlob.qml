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
    // Shared positions ensure rear dots and front dots drift in one field.
    // Every third mote lives IN FRONT of the glass rather than its source.
    readonly property var motes: [
        [-0.12,-0.045,0.037,0.92,0.78,0.20,[82,188,240]],
        [ 0.10,-0.092,0.031,0.84,0.96,1.00,[108,120,241]],
        [ 0.13, 0.052,0.028,1.03,0.88,1.80,[177,108,240]],
        [-0.08, 0.120,0.034,0.88,1.05,2.60,[231,109,195]],
        [ 0.02,-0.132,0.025,1.10,0.72,3.10,[92,211,199]],
        [-0.15, 0.022,0.023,0.79,0.94,4.00,[224,145,145]],
        [ 0.06, 0.135,0.030,0.90,0.90,4.80,[139,116,240]],
        [-0.01, 0.012,0.022,1.18,1.08,5.60,[82,169,225]],
        [ 0.17,-0.015,0.022,0.73,1.13,2.31,[198,96,203]],
        [-0.10,-0.122,0.027,1.14,0.80,3.56,[106,163,245]],
        [ 0.04, 0.073,0.026,0.85,1.06,1.73,[88,219,211]],
        [-0.035,0.165,0.022,1.12,0.77,4.47,[171,106,229]]
    ]
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
            frontField.requestPaint()
        }
    }
    onModeChanged: { field.requestPaint(); frontField.requestPaint() }
    onInputLevelChanged: { if (reduceMotion) { field.requestPaint(); frontField.requestPaint() } }
    onOutputLevelChanged: { if (reduceMotion) { field.requestPaint(); frontField.requestPaint() } }
    onReduceMotionChanged: { field.requestPaint(); frontField.requestPaint() }

    // Z0: diffuse cloud, bridges and REAR motes. No glass/front dots
    // can ever enter this offscreen texture: this is the depth boundary.
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
                const alpha = 0.255 + e * 0.095
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
            // Slow translucent color bridges overlap the six larger lobes.
            // They unify the cyan, blue, purple and magenta rather than
            // allowing each color to read as a separate circular bubble.
            const bridges = [
                [-0.045, 0.018, 0.29, 0.76, [105, 120, 234]],
                [ 0.049,-0.024, 0.27, 1.08, [184, 102, 223]],
                [ 0.012, 0.052, 0.26, 0.89, [83, 167, 211]]
            ]
            for (let i = 0; i < bridges.length; i++) {
                const b = bridges[i]
                const bx = w * (0.5 + b[0] + 0.026 * Math.sin(t * b[3] + i * 2.1))
                const by = h * (0.5 + b[1] + 0.026 * Math.cos(t * b[3] * 0.84 + i))
                const r = size * (b[2] + 0.015 * e)
                const rgb = b[4].join(",")
                const bridge = ctx.createRadialGradient(bx, by, 0, bx, by, r)
                bridge.addColorStop(0, "rgba(" + rgb + "," + (0.13 + 0.04 * e) + ")")
                bridge.addColorStop(0.50, "rgba(" + rgb + ",0.07)")
                bridge.addColorStop(1, "rgba(" + rgb + ",0)")
                ctx.fillStyle = bridge
                ctx.fillRect(bx - r, by - r, r * 2, r * 2)
            }

            // Soft micro-lights drift and change shape inside the cloud.
            // Their gradient edges stay completely transparent; these are
            // atmospheric lights, never sharp star points or hard dots.
            // [x, y, radius, x-rate, y-rate, phase, rgb]
            const motes = blob.motes
            for (let i = 0; i < motes.length; i++) {
                if (i % 3 === 0) continue // these four are foreground, not bent
                const d = motes[i]
                const dx = w * (0.5 + d[0] + 0.029 * Math.sin(t * d[3] + d[5]))
                const dy = h * (0.5 + d[1] + 0.029 * Math.cos(t * d[4] + d[5]))
                const breatheDot = 1 + 0.17 * Math.sin(t * 1.22 + d[5])
                const radius = size * (d[2] + 0.004 * e) * breatheDot
                const rgb = d[6].join(",")
                const alpha = (0.24 + 0.11 * e) *
                              (0.78 + 0.22 * Math.sin(t * 0.83 + d[5]) ** 2)
                ctx.save()
                ctx.translate(dx, dy)
                ctx.rotate(0.35 * Math.sin(t * 0.58 + d[5]))
                ctx.scale(1.03 + 0.19 * Math.sin(t * 0.84 + i),
                          0.93 + 0.15 * Math.cos(t * 0.92 + i))
                const mote = ctx.createRadialGradient(0, 0, 0, 0, 0, radius)
                mote.addColorStop(0, "rgba(" + rgb + "," + alpha + ")")
                mote.addColorStop(0.31, "rgba(" + rgb + "," + alpha * 0.68 + ")")
                mote.addColorStop(0.72, "rgba(" + rgb + "," + alpha * 0.15 + ")")
                mote.addColorStop(1, "rgba(" + rgb + ",0)")
                ctx.fillStyle = mote
                ctx.beginPath()
                ctx.arc(0, 0, radius, 0, 6.2831853)
                ctx.fill()
                ctx.restore()
            }

            const cx = w * (0.5 + 0.019 * Math.sin(t * 0.61))
            const cy = h * (0.5 + 0.019 * Math.cos(t * 0.79))
            const core = ctx.createRadialGradient(cx, cy, 0, cx, cy, size * 0.29)
            core.addColorStop(0, "rgba(148,118,228," + (0.10 + e * 0.05) + ")")
            core.addColorStop(0.34, "rgba(88,160,235,0.07)")
            core.addColorStop(0.60, "rgba(102,92,220,0.05)")
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


    // Backward-only texture for refractive dots. The captured source does not
    // include desktopLens or frontField; no feedback, no double refraction.
    ShaderEffectSource {
        id: rearSource
        objectName: "citronRearOnlyTexture"
        width: blob.width
        height: blob.height
        visible: false
        sourceItem: field
        hideSource: false
        live: blob.running && blob.visible
        recursive: false
        textureSize: Qt.size(Math.max(1, Math.round(blob.width)),
                             Math.max(1, Math.round(blob.height)))
    }

    // Z1: genuine thick-glass disks refract the DESKTOP (using the shell's
    // existing DesktopBackdrop/Glass) and the rear-only texture (the pre-
    // compiled glasslens.frag.qsb). Foreground motes are drawn afterwards.
    Item {
        id: middleGlass
        objectName: "citronGlassDepthLayer"
        anchors.fill: parent
        Repeater {
            model: [
                [0.35, 0.39, 58, 0.72, 0.40, 0.0, 1.06],
                [0.59, 0.36, 48, 0.64, 0.71, 1.4, 1.15],
                [0.48, 0.57, 68, 0.80, 0.62, 2.1, 1.18],
                [0.67, 0.54, 43, 0.98, 0.77, 3.1, 1.08],
                [0.27, 0.62, 37, 0.75, 0.89, 4.2, 1.03],
                [0.46, 0.27, 33, 0.85, 0.96, 5.0, 1.09]
            ]
            delegate: CitronGlassDot {
                required property var modelData
                readonly property real t: blob.reduceMotion ? 0.9 : blob.phase
                width: blob.width * modelData[2] / 360
                height: width
                x: blob.width * (modelData[0] +
                   0.025 * Math.sin(t * modelData[3] + modelData[5])) - width / 2
                y: blob.height * (modelData[1] +
                   0.025 * Math.cos(t * modelData[4] + modelData[5])) - height / 2
                rearTexture: rearSource
                running: blob.running
                phase: t + modelData[5]
                refraction: modelData[6] + (blob.reduceMotion ? 0 : blob.energy * 0.08)
            }
        }
    }

    // Z2: foreground motes draw AFTER lens refraction, and stay undistorted.
    Canvas {
        id: frontField
        objectName: "citronUnbentForegroundMotes"
        anchors.fill: parent
        renderTarget: Canvas.Image
        antialiasing: true
        onPaint: {
            const ctx = getContext("2d")
            const w = width, h = height, sz = Math.min(w, h)
            ctx.clearRect(0, 0, w, h)
            const t = blob.reduceMotion ? 1.14 : blob.phase
            const e = blob.reduceMotion ? blob.targetEnergy : blob.energy
            for (let i = 0; i < blob.motes.length; i += 3) {
                const d = blob.motes[i]
                const x = w * (0.5 + d[0] + 0.029 * Math.sin(t * d[3] + d[5]))
                const y = h * (0.5 + d[1] + 0.029 * Math.cos(t * d[4] + d[5]))
                const radius = sz * (d[2] + 0.004 * e) *
                               (1 + 0.17 * Math.sin(t * 1.22 + d[5]))
                const rgb = d[6].join(",")
                const alpha = 0.32 + 0.11 * e
                ctx.save()
                ctx.translate(x, y)
                ctx.rotate(0.35 * Math.sin(t * 0.58 + d[5]))
                ctx.scale(1.09 + 0.16 * Math.sin(t * 0.84 + i),
                          0.92 + 0.15 * Math.cos(t * 0.92 + i))
                const light = ctx.createRadialGradient(0, 0, 0, 0, 0, radius)
                light.addColorStop(0, "rgba(" + rgb + "," + alpha + ")")
                light.addColorStop(0.30, "rgba(" + rgb + "," + (alpha * 0.68) + ")")
                light.addColorStop(0.72, "rgba(" + rgb + "," + (alpha * 0.14) + ")")
                light.addColorStop(1, "rgba(" + rgb + ",0)")
                ctx.fillStyle = light
                ctx.beginPath()
                ctx.arc(0, 0, radius, 0, 6.2831853)
                ctx.fill()
                ctx.restore()
            }
        }
        Component.onCompleted: requestPaint()
    }
}
