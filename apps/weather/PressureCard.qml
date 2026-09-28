// Pressure: a gauge from low to high with the reading marked, and whether it's
// rising or falling.
import QtQuick
import "api.js" as Api

Card {
    id: card
    title: "Pressure"; symbol: "gauge"
    property real hpa: 1013
    property int trend: 0          // -1 falling, 0 steady, 1 rising
    property bool imperial: false

    readonly property real frac: Math.max(0, Math.min(1, (hpa - 970) / (1050 - 970)))

    Canvas {
        id: gauge
        width: 96; height: 96
        anchors.horizontalCenter: parent.horizontalCenter
        y: -6
        onPaint: {
            const ctx = getContext("2d"), c = width / 2, r = c - 2
            ctx.reset(); ctx.translate(c, c)
            const start = Math.PI * 0.75, span = Math.PI * 1.5, n = 48
            for (let i = 0; i <= n; i++) {
                const a = start + span * i / n
                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.3); ctx.lineWidth = 1.4
                ctx.beginPath(); ctx.moveTo(Math.cos(a) * (r - 8), Math.sin(a) * (r - 8)); ctx.lineTo(Math.cos(a) * r, Math.sin(a) * r); ctx.stroke()
            }
            const a = start + span * card.frac
            ctx.strokeStyle = "#ffffff"; ctx.lineWidth = 3.5; ctx.lineCap = "round"
            ctx.beginPath(); ctx.moveTo(Math.cos(a) * (r - 12), Math.sin(a) * (r - 12)); ctx.lineTo(Math.cos(a) * (r + 1), Math.sin(a) * (r + 1)); ctx.stroke()
        }
        Connections { target: card; function onFracChanged() { gauge.requestPaint() } }
        Column {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 4
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: card.trend > 0 ? "↑" : card.trend < 0 ? "↓" : "="
                px: 15; w: Font.Bold
            }
            Label { anchors.horizontalCenter: parent.horizontalCenter; text: Api.pressure(card.hpa, card.imperial); px: 15; w: Font.DemiBold }
            Label { anchors.horizontalCenter: parent.horizontalCenter; text: Api.pressureUnit(card.imperial); px: 10; w: Font.DemiBold; alpha: 0.9 }
        }
    }
    Label { anchors { bottom: parent.bottom; left: parent.left; leftMargin: 14 } text: "Low"; px: 12; w: Font.DemiBold }
    Label { anchors { bottom: parent.bottom; right: parent.right; rightMargin: 12 } text: "High"; px: 12; w: Font.DemiBold }
}
