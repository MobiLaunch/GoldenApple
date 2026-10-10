// The 10-day forecast: day, condition, chance of rain, and each day's range on
// a bar spanning the coldest to the warmest of the ten, as Weather draws it.
import QtQuick
import "api.js" as Api

Card {
    id: card
    property var f: null
    property bool imperial: false

    readonly property int first: f ? Math.max(0, f.daily.time.indexOf(Api.dateOf(f.current.time))) : 0
    readonly property var days: {
        if (!f) return []
        const d = f.daily, out = []
        for (let i = first; i < Math.min(d.time.length, first + 10); i++)
            out.push({ name: i === first ? "Today" : Api.weekday(d.time[i]),
                       icon: Api.icon(d.weather_code[i], 1), pop: d.precipitation_probability_max[i] ?? 0,
                       lo: d.temperature_2m_min[i], hi: d.temperature_2m_max[i], today: i === first })
        return out
    }
    readonly property real minT: days.length ? Math.min(...days.map((x) => x.lo)) : 0
    readonly property real maxT: days.length ? Math.max(...days.map((x) => x.hi)) : 1

    Column {
        x: -12; y: -card.headerHeight + 6
        width: parent.width + 24
        Repeater {
            model: card.days
            delegate: Item {
                id: row
                required property var modelData
                required property int index
                width: parent.width; height: (card.height - 12) / 10

                Rectangle {
                    visible: row.index > 0
                    x: 16; width: parent.width - 32; height: 0.5
                    color: "#33ffffff"
                }
                Label {
                    x: 16; anchors.verticalCenter: parent.verticalCenter
                    text: modelData.name; px: 15; w: Font.DemiBold
                }
                WxIcon {
                    id: dayIcon
                    x: 80; y: modelData.pop >= 20 ? 7 : (parent.height - height) / 2
                    name: modelData.icon; size: 22
                }
                Label {
                    anchors.horizontalCenter: dayIcon.horizontalCenter
                    y: 29
                    visible: modelData.pop >= 20
                    text: modelData.pop + "%"
                    color: "#5fd0ff"; px: 10; w: Font.Bold
                }
                Label {
                    anchors { right: bar.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    text: Api.temp(modelData.lo, card.imperial)
                    px: 15; w: Font.DemiBold; alpha: 0.6
                }
                // Range bar
                Rectangle {
                    id: bar
                    x: 158; width: parent.width - 158 - 56; height: 5; radius: 2.5
                    anchors.verticalCenter: parent.verticalCenter
                    color: "#26000000"
                    readonly property real span: Math.max(1, card.maxT - card.minT)
                    Rectangle {
                        x: (modelData.lo - card.minT) / bar.span * bar.width
                        width: Math.max(height, (modelData.hi - modelData.lo) / bar.span * bar.width)
                        height: parent.height; radius: 2.5
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: Qt.rgba(...Api.tempColor(modelData.lo), 1) }
                            GradientStop { position: 1; color: Qt.rgba(...Api.tempColor(modelData.hi), 1) }
                        }
                    }
                    // Today: where the temperature is now.
                    Rectangle {
                        visible: modelData.today && !!card.f
                        width: 7; height: 7; radius: 3.5
                        anchors.verticalCenter: parent.verticalCenter
                        x: card.f ? Math.max(0, Math.min(bar.width, (card.f.current.temperature_2m - card.minT) / bar.span * bar.width)) - 3.5 : 0
                        color: "#ffffff"
                        border { width: 1.5; color: "#40000000" }
                    }
                }
                Label {
                    anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    text: Api.temp(modelData.hi, card.imperial)
                    px: 15; w: Font.DemiBold
                }
            }
        }
    }
}
