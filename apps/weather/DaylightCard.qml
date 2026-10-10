// Daylight: how long the day is, compared with yesterday, on a 24-hour bar.
import QtQuick
import "api.js" as Api

Card {
    id: card
    title: "Daylight"; symbol: "sun"
    property var f: null
    property bool h12: true

    readonly property int today: f ? Math.max(0, f.daily.time.indexOf(Api.dateOf(f.current.time))) : 0
    readonly property real length: f ? f.daily.daylight_duration[today] : 0
    readonly property real diff: f && today > 0 ? (length - f.daily.daylight_duration[today - 1]) / 60 : 0

    Label { y: 2; text: Api.duration(card.length); px: 26; w: Font.Normal; wrapMode: Text.NoWrap }
    Label {
        y: 36
        text: Math.round(Math.abs(card.diff)) === 0 ? "About the same as yesterday."
            : Math.round(Math.abs(card.diff)) + " min " + (card.diff < 0 ? "shorter" : "longer") + " than yesterday."
        px: 12; w: Font.DemiBold
    }
    Item {
        id: dayBar
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 16 }
        height: 8
        readonly property real riseX: card.f ? Api.minutes(card.f.daily.sunrise[card.today]) / 1440 * width : 0
        readonly property real setX: card.f ? Api.minutes(card.f.daily.sunset[card.today]) / 1440 * width : width
        Rectangle { anchors.fill: parent; radius: 4; color: "#33000000" }
        Rectangle {
            x: dayBar.riseX; width: dayBar.setX - dayBar.riseX; height: parent.height; radius: 4
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "#ffb340" }
                GradientStop { position: 0.5; color: "#ffe27a" }
                GradientStop { position: 1; color: "#ff9f40" }
            }
        }
        Rectangle {
            visible: !!card.f
            width: 3; height: 14; radius: 1.5
            anchors.verticalCenter: parent.verticalCenter
            x: card.f ? Api.minutes(card.f.current.time) / 1440 * parent.width - 1.5 : 0
            color: "#ffffff"
            border { width: 0.5; color: "#40000000" }
        }
        Label {
            y: 12; x: Math.max(0, dayBar.riseX - width / 2)
            text: card.f ? Api.clockText(card.f.daily.sunrise[card.today], card.h12) : ""
            px: 10; w: Font.DemiBold; alpha: 0.8
        }
        Label {
            y: 12; x: Math.min(dayBar.width - width, dayBar.setX - width / 2)
            text: card.f ? Api.clockText(card.f.daily.sunset[card.today], card.h12) : ""
            px: 10; w: Font.DemiBold; alpha: 0.8
        }
    }
}
