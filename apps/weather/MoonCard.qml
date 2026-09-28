// The moon tonight, lit to its phase, and how long until it's full.
import QtQuick
import "api.js" as Api

Card {
    id: card
    property real age: Api.moonAge(Date.now())
    title: Api.moonPhaseName(age); symbol: "moon"

    Canvas {
        id: moon
        width: 74; height: 74
        anchors.horizontalCenter: parent.horizontalCenter
        y: 4
        onPaint: {
            const ctx = getContext("2d"), r = width / 2
            ctx.reset()
            ctx.translate(r, r)
            const face = (alpha) => {
                const g = ctx.createRadialGradient(-r * 0.3, -r * 0.3, r * 0.1, 0, 0, r)
                g.addColorStop(0, Qt.rgba(0.95, 0.95, 0.95, alpha))
                g.addColorStop(1, Qt.rgba(0.62, 0.64, 0.66, alpha))
                ctx.fillStyle = g
                ctx.beginPath(); ctx.arc(0, 0, r, 0, Math.PI * 2); ctx.fill()
                // Maria: soft darker patches.
                for (const m of [[-0.22, -0.28, 0.34], [0.18, -0.32, 0.24], [0.26, 0.08, 0.3], [-0.08, 0.22, 0.22], [-0.42, 0.12, 0.16]]) {
                    const mg = ctx.createRadialGradient(m[0] * r, m[1] * r, 0, m[0] * r, m[1] * r, m[2] * r)
                    mg.addColorStop(0, Qt.rgba(0.40, 0.42, 0.45, 0.30 * alpha))
                    mg.addColorStop(1, Qt.rgba(0.40, 0.42, 0.45, 0))
                    ctx.fillStyle = mg
                    ctx.fillRect(m[0] * r - m[2] * r, m[1] * r - m[2] * r, m[2] * r * 2, m[2] * r * 2)
                }
            }
            face(0.18)   // the unlit part, faintly (earthshine)
            // Lit part: one half of the disc, bounded by the terminator (a half
            // ellipse whose width follows the phase).
            const p = card.age / Api.SYNODIC
            const waxing = p < 0.5
            const k = Math.cos(2 * Math.PI * p)          // 1 new, 0 quarter, -1 full
            const side = waxing ? 1 : -1                 // lit limb on the right while waxing
            const ex = side * k * r                      // terminator's x at the equator
            const kappa = 0.5523
            ctx.save()
            ctx.beginPath()
            ctx.moveTo(0, -r)
            ctx.arc(0, 0, r, -Math.PI / 2, Math.PI / 2, side < 0)
            ctx.bezierCurveTo(ex * kappa * 1.0 + 0, r, ex, r * kappa, ex, 0)
            ctx.bezierCurveTo(ex, -r * kappa, ex * kappa, -r, 0, -r)
            ctx.closePath()
            ctx.clip()
            face(1)
            ctx.restore()
        }
    }
    Label {
        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
        readonly property int d: Api.daysToFull(card.age)
        text: d === 0 ? "Full Moon tonight" : "Full Moon: " + d + (d === 1 ? " day" : " days")
        px: 12; w: Font.DemiBold
    }
}
