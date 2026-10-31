// "Conditions": the next 24 hours, with sunrise and sunset slotted in where they
// fall, switchable between temperature, chance of precipitation and wind.
import QtQuick
import "../lib"
import "../lib/theme"
import "api.js" as Api

Card {
    id: card
    property var f: null            // Open-Meteo forecast
    property bool imperial: false
    property bool h12: true
    property string mode: "temp"    // temp | precip | wind

    readonly property var hours: {
        if (!f) return []
        const h = f.hourly, now = f.current.time.substr(0, 13)
        let i = h.time.findIndex((t) => t.substr(0, 13) === now)
        if (i < 0) return []
        const events = []
        for (const key of ["sunrise", "sunset"])
            for (const t of f.daily[key]) events.push({ t: t, kind: key })
        const out = []
        const end = Math.min(h.time.length, i + 25)
        for (let k = i; k < end; k++) {
            const c = Api.clock(h.time[k], card.h12, false)
            out.push({
                label: k === i ? "Now" : c[0], suffix: k === i ? "" : c[1],
                icon: Api.icon(h.weather_code[k], h.is_day[k]),
                pop: h.precipitation_probability[k] ?? 0,
                value: card.mode === "temp" ? Api.temp(h.temperature_2m[k], card.imperial)
                     : card.mode === "precip" ? (h.precipitation_probability[k] ?? 0) + "%"
                     : String(Api.speed(h.wind_speed_10m[k], card.imperial)),
            })
            // A sunrise or sunset inside this hour gets its own column after it.
            const ev = events.find((e) => e.t.substr(0, 13) === h.time[k].substr(0, 13) && (k > i || e.t > f.current.time))
            if (ev && k + 1 < end) {
                const c2 = Api.clock(ev.t, card.h12, true)
                out.push({ label: c2[0], suffix: c2[1], icon: ev.kind, pop: 0,
                           value: ev.kind === "sunrise" ? "Sunrise" : "Sunset", event: true })
            }
        }
        return out
    }

    Label {
        x: 12; y: 10 - card.headerHeight
        text: "Conditions"
        px: 16; w: Font.DemiBold
    }
    Label {
        x: 12; y: 30 - card.headerHeight
        text: card.mode === "temp" ? "Temperature (" + (card.imperial ? "°F" : "°C") + ")"
            : card.mode === "precip" ? "Chance of Precipitation" : "Wind Speed (" + Api.speedUnit(card.imperial) + ")"
        px: 12; alpha: 0.9
    }

    // Segmented control: temperature, precipitation, wind.
    Rectangle {
        x: parent.width - width; y: 10 - card.headerHeight
        width: seg.width + 6; height: 32; radius: 16
        color: "#1affffff"
        Row {
            id: seg
            anchors.centerIn: parent
            Repeater {
                model: [{ m: "temp", i: "cloud-sun" }, { m: "precip", s: "drop" }, { m: "wind", s: "wind" }]
                delegate: Item {
                    required property var modelData
                    width: 38; height: 26
                    Rectangle {
                        anchors.fill: parent; radius: 13
                        color: "#ffffff"
                        opacity: card.mode === modelData.m ? 0.32 : segHover.hovered ? 0.1 : 0
                        Behavior on opacity { NumberAnimation { duration: 140 } }
                    }
                    WxIcon { anchors.centerIn: parent; visible: !!modelData.i; name: modelData.i ?? ""; size: 17 }
                    Symbol { anchors.centerIn: parent; visible: !!modelData.s; name: modelData.s ?? ""; tone: "white"; size: 13 }
                    HoverHandler { id: segHover }
                    TapHandler { onTapped: card.mode = modelData.m }
                }
            }
        }
    }

    ListView {
        id: list
        x: -12; y: 52 - card.headerHeight
        width: parent.width + 24; height: 86
        orientation: ListView.Horizontal
        clip: true
        leftMargin: 6; rightMargin: 6
        boundsBehavior: Flickable.StopAtBounds
        model: card.hours
        delegate: Item {
            required property var modelData
            width: modelData.event ? 62 : 54; height: list.height
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: hourNum.width + hourSuffix.width; height: hourNum.height
                Label { id: hourNum; text: modelData.label; px: 12; w: Font.DemiBold; wrapMode: Text.NoWrap }
                Label { id: hourSuffix; x: hourNum.width; anchors.baseline: hourNum.baseline; text: modelData.suffix; px: 9; w: Font.DemiBold; wrapMode: Text.NoWrap }
            }
            WxIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                y: modelData.pop >= 20 && card.mode === "temp" ? 20 : 25
                name: modelData.icon; size: 22
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 43
                visible: modelData.pop >= 20 && card.mode === "temp" && !modelData.event
                text: modelData.pop + "%"
                color: "#5fd0ff"; px: 10; w: Font.Bold
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 60
                text: modelData.value
                px: 15; w: Font.DemiBold; wrapMode: Text.NoWrap
            }
        }
    }
}
