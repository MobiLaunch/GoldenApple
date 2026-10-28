import QtQuick
QtObject {
    enum Precision { Hours, Minutes, Seconds }
    property int precision: SystemClock.Seconds
    property bool enabled: true
    // A fixed moment, so previews are comparable: Sunday 4 October, 9:41.
    // GG_PREVIEW_LIVE_CLOCK=1 lets it run, at its precision (--idle-frames).
    property date date: new Date(2026, 9, 4, 9, 41, 0)
    readonly property int hours: date.getHours()
    readonly property int minutes: date.getMinutes()
    readonly property int seconds: date.getSeconds()
    property Timer __tick: Timer {
        running: enabled && Quickshell.env("GG_PREVIEW_LIVE_CLOCK") === "1"
        interval: precision === SystemClock.Seconds ? 1000 : precision === SystemClock.Minutes ? 60000 : 3600000
        repeat: true
        onTriggered: date = new Date()
    }
}
