// Sunset (or sunrise, whichever is next), with the sun's path through the day
// and where it is now.
import QtQuick
import "../lib/theme"
import "api.js" as Api

Card {
    id: card
    property var f: null
    property bool h12: true

    readonly property string now: f ? f.current.time : ""
    readonly property int today: f ? Math.max(0, f.daily.time.indexOf(Api.dateOf(now))) : 0
    readonly property string rise: f ? f.daily.sunrise[today] : ""
    readonly property string set: f ? f.daily.sunset[today] : ""
    // Before sunrise: today's sunrise; daytime: sunset; evening: tomorrow's sunrise.
    readonly property string nextKind: !f ? "sunset" : now < rise ? "sunrise" : now < set ? "sunset" : "sunrise"
    readonly property string nextTime: !f ? "" : now < rise ? rise : now < set ? set : (f.daily.sunrise[today + 1] ?? rise)
    readonly property string otherLine: !f ? "" : nextKind === "sunset" ? "Sunrise: " + Api.clockText(rise, h12)
                                             : "Sunset: " + Api.clockText(now < rise ? set : (f.daily.sunset[today + 1] ?? set), h12)
    title: nextKind === "sunset" ? "Sunset" : "Sunrise"
    symbol: "sunset"

    Item {
        y: 2
        readonly property var c: card.nextTime ? Api.clock(card.nextTime, card.h12) : ["--", ""]
        Label { id: big; text: parent.c[0]; px: 30; w: Font.Normal; wrapMode: Text.NoWrap }
        Label { x: big.width; anchors.baseline: big.baseline; text: parent.c[1]; px: 20; w: Font.Normal; wrapMode: Text.NoWrap }
    }

    Canvas {
        id: path
        x: -12; y: 42
        width: parent.width + 24; height: 50
        readonly property real horizon: 30
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            if (!card.f) return
            const w = width, riseM = Api.minutes(card.rise), setM = Api.minutes(card.set)
            const noon = (riseM + setM) / 2
            const c0 = Math.cos(2 * Math.PI * (riseM - noon) / 1440)
            const A = 22
            const yAt = (m) => horizon - A * (Math.cos(2 * Math.PI * (m - noon) / 1440) - c0) / (1 - c0)
            const trace = () => { ctx.beginPath(); for (let x = 0; x <= w; x += 2) { const m = x / w * 1440; x === 0 ? ctx.moveTo(x, yAt(m)) : ctx.lineTo(x, yAt(m)) } }
            // Below the horizon: dim
            ctx.lineWidth = 2.5; ctx.lineCap = "round"
            ctx.save(); ctx.beginPath(); ctx.rect(0, horizon, w, height); ctx.clip()
            ctx.strokeStyle = Qt.rgba(0, 0, 0, 0.22); trace(); ctx.stroke(); ctx.restore()
            ctx.save(); ctx.beginPath(); ctx.rect(0, 0, w, horizon); ctx.clip()
            ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.55); trace(); ctx.stroke(); ctx.restore()
            ctx.fillStyle = Qt.rgba(1, 1, 1, 0.35); ctx.fillRect(0, horizon, w, 1)
            // The sun
            const nm = Api.minutes(card.now), sx = nm / 1440 * w, sy = yAt(nm)
            const up = sy <= horizon
            const g = ctx.createRadialGradient(sx, sy, 0, sx, sy, 12)
            g.addColorStop(0, Qt.rgba(1, 1, 1, up ? 0.7 : 0.2)); g.addColorStop(1, Qt.rgba(1, 1, 1, 0))
            ctx.fillStyle = g; ctx.fillRect(sx - 12, sy - 12, 24, 24)
            ctx.fillStyle = up ? "#ffffff" : Qt.rgba(1, 1, 1, 0.5)
            ctx.beginPath(); ctx.arc(sx, sy, 4.5, 0, Math.PI * 2); ctx.fill()
        }
        Connections { target: card; function onFChanged() { path.requestPaint() } }
    }
    Label {
        anchors.bottom: parent.bottom
        text: card.otherLine; px: 12; w: Font.DemiBold
    }
}
