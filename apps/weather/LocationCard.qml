// A place in the sidebar: its sky, name, local time, conditions and temperature.
import QtQuick
import "api.js" as Api

Item {
    id: card
    property var place: null
    property var f: null
    property bool imperial: false
    property bool h12: true
    property bool selected: false
    signal activated()
    signal menuRequested(real x, real y)

    height: 92
    readonly property var cur: f ? f.current : null
    readonly property int today: f ? Math.max(0, f.daily.time.indexOf(Api.dateOf(f.current.time))) : 0

    Sky {
        anchors.fill: parent
        radius: 14
        kind: card.cur ? Api.sky(card.cur.weather_code, card.cur.is_day) : "cloudy"
        seed: Math.round(Math.abs((card.place?.lat ?? 0) * 1000)) + 3
    }
    Rectangle {
        anchors.fill: parent
        radius: 14
        color: "transparent"
        border { width: card.selected ? 2 : 0.5; color: card.selected ? "#e6ffffff" : "#33ffffff" }
    }
    Label {
        x: 12; y: 9
        width: parent.width - 90
        elide: Text.ElideRight; wrapMode: Text.NoWrap
        text: card.place?.home ? "My Location" : card.place?.name ?? ""
        px: 17; w: Font.Bold
    }
    Label {
        x: 12; y: 31
        text: card.place?.home ? card.place.name
            : card.f ? Api.clockText(Api.placeNow(card.f.utc_offset_seconds), card.h12) : ""
        px: 12; w: Font.DemiBold
    }
    Label {
        x: 12; anchors { bottom: parent.bottom; bottomMargin: 9 }
        width: parent.width - 110
        elide: Text.ElideRight; wrapMode: Text.NoWrap
        text: card.cur ? Api.conditionName(card.cur.weather_code) : ""
        px: 12; w: Font.DemiBold
    }
    Label {
        anchors { right: parent.right; rightMargin: 12; top: parent.top; topMargin: 2 }
        text: card.cur ? Api.temp(card.cur.temperature_2m, card.imperial) : "--"
        px: 38; w: Font.Light; wrapMode: Text.NoWrap
    }
    Label {
        anchors { right: parent.right; rightMargin: 12; bottom: parent.bottom; bottomMargin: 9 }
        text: card.f ? "H:" + Api.temp(card.f.daily.temperature_2m_max[card.today], card.imperial)
                     + "  L:" + Api.temp(card.f.daily.temperature_2m_min[card.today], card.imperial) : ""
        px: 12; w: Font.DemiBold; wrapMode: Text.NoWrap
    }
    TapHandler { onTapped: card.activated() }
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: (ev) => card.menuRequested(ev.position.x, ev.position.y)
    }
}
