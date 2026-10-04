import QtQuick
QtObject {
    enum Precision { Hours, Minutes, Seconds }
    property int precision: SystemClock.Seconds
    property bool enabled: true
    // A fixed moment, so previews are comparable: Sunday 4 October, 9:41.
    readonly property date date: new Date(2026, 9, 4, 9, 41, 0)
    readonly property int hours: 9
    readonly property int minutes: 41
    readonly property int seconds: 0
}
