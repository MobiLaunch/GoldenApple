// Refractive thick-glass mote. Its two independent backdrops are intentional:
// - Glass bends the REAL desktop behind this Wayland overlay via Backdrops.
// - ShaderEffect bends only the rear Citron haze and rear motes.
// The foreground motes live ABOVE this component, never in either source.
// Reuse the existing compiled Qt 6 glasslens shader (not inline GLSL).
import QtQuick
import "../" as Shared
import "../theme"

Item {
    id: lens
    objectName: "citronGlassMote"
    implicitWidth: 56
    implicitHeight: 56
    property var rearTexture: null
    property bool running: true
    property real phase: 0
    property real refraction: 1
    readonly property bool gpu: GraphicsInfo.api !== GraphicsInfo.Software
        && !Theme.reduceTransparency
    readonly property real diameter: Math.min(width, height)
    readonly property real r: diameter * 0.5

    // Sample the actual wallpaper/windows UNDER Citron. Disable detached
    // shadows: offscreen shadows used to create rectangular crop artefacts.
    Shared.Glass {
        id: desktopLens
        anchors.fill: parent
        role: "clear"
        radius: lens.r
        lens: lens.r * 0.31
        tint: "#0affffff"
        rim: "#16ffffff"
        rimLow: "#08ffffff"
        edge: "#120d1630"
        shine: "#0bffffff"
        shadowEnabled: false
    }

    // Existing compiled shader's origin is the dot's top-left in a texture
    // covering the WHOLE blob. Never sample a texture containing front motes.
    ShaderEffect {
        id: rearRefraction
        anchors.fill: parent
        visible: lens.gpu && !!lens.rearTexture
        property variant source: lens.rearTexture
        property size size: Qt.size(width, height)
        property real radius: lens.r
        property real bevel: lens.diameter * 0.38
        property real strength: Math.min(14, lens.diameter * 0.19) * lens.refraction
        property real dome: 0.11
        property real dispersion: 0.14
        property real blur: 0.65
        property point origin: Qt.point(lens.x, lens.y)
        property size texSize: lens.rearTexture
            ? Qt.size(lens.rearTexture.width, lens.rearTexture.height)
            : Qt.size(1, 1)
        fragmentShader: Qt.resolvedUrl("../shaders/glasslens.frag.qsb")
    }

    // Surface optics are visible in both hardware and software renderers:
    // bright off-centre catchlight, inner falloff, beveled edge and no shadow.
    Canvas {
        id: optics
        anchors.fill: parent
        antialiasing: true
        renderTarget: Canvas.Image
        onPaint: {
            const ctx = getContext("2d")
            const w = width, h = height, r = Math.min(w, h) * 0.5
            if (r <= 0) return
            ctx.clearRect(0, 0, w, h)
            const cx = w * 0.5, cy = h * 0.5
            const roll = Theme.reduceMotion ? 0 : Math.sin(lens.phase * 0.61)

            // Edge thickness, with deliberately uneven illumination.
            const edge = ctx.createRadialGradient(cx, cy, r * 0.55, cx, cy, r)
            edge.addColorStop(0, "rgba(250,247,255,0)")
            edge.addColorStop(0.66, "rgba(235,230,255,0.025)")
            edge.addColorStop(0.84, "rgba(225,238,255,0.11)")
            edge.addColorStop(0.97, "rgba(210,239,255,0.23)")
            edge.addColorStop(1, "rgba(255,255,255,0)")
            ctx.fillStyle = edge
            ctx.beginPath()
            ctx.arc(cx, cy, r, 0, Math.PI * 2)
            ctx.fill()

            ctx.beginPath()
            ctx.arc(cx, cy, r - 1.2, -2.8 + roll * 0.08, 0.0 + roll * 0.08)
            ctx.strokeStyle = "rgba(250,251,255,0.46)"
            ctx.lineWidth = 1.05
            ctx.stroke()
            ctx.beginPath()
            ctx.arc(cx, cy, r - 1.8, 0.45, 2.15)
            ctx.strokeStyle = "rgba(29,26,77,0.34)"
            ctx.lineWidth = 1.3
            ctx.stroke()

            const hx = w * (0.33 + roll * 0.025)
            const hy = h * 0.27
            const shine = ctx.createRadialGradient(hx, hy, 0, hx, hy, r * 0.47)
            shine.addColorStop(0, "rgba(255,255,255,0.37)")
            shine.addColorStop(0.36, "rgba(235,244,255,0.14)")
            shine.addColorStop(1, "rgba(255,255,255,0)")
            ctx.fillStyle = shine
            ctx.fillRect(0, 0, w, h)
        }
        Component.onCompleted: requestPaint()
    }

    onPhaseChanged: if (running && !Theme.reduceMotion) optics.requestPaint()
}
