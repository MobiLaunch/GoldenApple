// Minute-accurate clock that works in any Qt Quick host (Quickshell or SDDM),
// unlike Quickshell's SystemClock.
import QtQuick

QtObject {
    property date now: new Date()
    property Timer _tick: Timer {
        interval: 1000 * (60 - new Date().getSeconds())
        running: true
        repeat: true
        onTriggered: { now = new Date(); interval = 60000 }
    }
}
