// Wind: a compass with the speed in the middle and an arrow showing which way
// the wind blows, and the gusts below.
import QtQuick
import "../lib/theme"
import "api.js" as Api

Card {
    id: card
    title: "Wind"; symbol: "wind"
    property real speed: 0          // display units
    property real gusts: 0
    property real direction: 0      // degrees the wind comes from
    property bool imperial: false

    Canvas {
        id: dial
        width: 76; height: 76
        anchors.horizontalCenter: parent.horizontalCenter
        y: -4
        onPaint: {
            const ctx = getContext("2d"), c = width / 2, r = c - 1
            ctx.reset()
            ctx.translate(c, c)
            for (let i = 0; i < 72; i++) {
                const a = i * Math.PI / 36, major = i % 18 === 0
                ctx.strokeStyle = Qt.rgba(1, 1, 1, major ? 0.8 : 0.35)
                ctx.lineWidth = major ? 1.6 : 1
                ctx.beginPath()
                ctx.moveTo(Math.sin(a) * (r - (major ? 7 : 5)), -Math.cos(a) * (r - (major ? 7 : 5)))
                ctx.lineTo(Math.sin(a) * r, -Math.cos(a) * r)
                ctx.stroke()
            }
            // Arrow: from the side the wind comes from to the side it goes to.
            const to = (card.direction + 180) * Math.PI / 180
            const dx = Math.sin(to), dy = -Math.cos(to)
            ctx.strokeStyle = "#ffffff"; ctx.fillStyle = "#ffffff"; ctx.lineWidth = 2; ctx.lineCap = "round"
            ctx.beginPath(); ctx.moveTo(dx * 16, dy * 16); ctx.lineTo(dx * (r - 3), dy * (r - 3)); ctx.stroke()
            ctx.beginPath(); ctx.moveTo(-dx * 16, -dy * 16); ctx.lineTo(-dx * (r - 6), -dy * (r - 6)); ctx.stroke()
            ctx.beginPath(); ctx.arc(-dx * (r - 5), -dy * (r - 5), 2.6, 0, Math.PI * 2); ctx.fill()
            const hx = dx * (r - 1), hy = dy * (r - 1), px = -dy, py = dx
            ctx.beginPath()
            ctx.moveTo(hx, hy)
            ctx.lineTo(hx - dx * 8 + px * 4.5, hy - dy * 8 + py * 4.5)
            ctx.lineTo(hx - dx * 8 - px * 4.5, hy - dy * 8 - py * 4.5)
            ctx.closePath(); ctx.fill()
        }
        Connections { target: card; function onDirectionChanged() { dial.requestPaint() } }
        Repeater {
            model: [["N", 0, -1, 0], ["E", 1, 0, 90], ["S", 0, 1, 180], ["W", -1, 0, 270]]
            delegate: Label {
                required property var modelData
                // Hidden where the arrow crosses it.
                readonly property real off: Math.abs(((card.direction - modelData[3]) % 180 + 180) % 180)
                visible: off > 25 && off < 155
                x: dial.width / 2 + modelData[1] * 24 - width / 2
                y: dial.height / 2 + modelData[2] * 24 - height / 2
                text: modelData[0]; px: 9; w: Font.Bold; alpha: 0.85
            }
        }
        Column {
            anchors.centerIn: parent
            Label { anchors.horizontalCenter: parent.horizontalCenter; text: Math.round(card.speed); px: 15; w: Font.DemiBold }
            Label { anchors.horizontalCenter: parent.horizontalCenter; text: Api.speedUnit(card.imperial); px: 9; w: Font.DemiBold; y: -2 }
        }
    }
    Label {
        anchors.bottom: parent.bottom
        text: "Gusts: " + Math.round(card.gusts) + " " + Api.speedUnit(card.imperial) + " " + Api.compass(card.direction)
        px: 12; w: Font.DemiBold
    }
}
