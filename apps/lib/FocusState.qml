import QtQuick
import "FocusPolicy.js" as Policy

QtObject {
    id: status
    property var policy: ({})
    property real now: Date.now()
    property bool ticking: true
    readonly property var state: Policy.state(policy, now)
    readonly property bool active: state.active
    readonly property real until: state.until
    readonly property string summary: !active ? (state.source === "paused" ? "Paused for this scheduled period" : "Off")
        : until ? (state.source === "schedule" ? "Scheduled until " : "Until ") + Qt.formatTime(new Date(until), "h:mm AP")
        : "Until turned off"
    function start(minutes) { return Policy.start(minutes, Date.now()) }
    function stop() { return Policy.stop(policy, Date.now()) }
    function allows(key, urgency) { return Policy.allows(policy, key, urgency) }
    function permits(key, urgency) { return !Policy.state(policy, Date.now()).active || allows(key, urgency) }
    property Timer clock: Timer { interval: 1000; running: status.ticking; repeat: true; onTriggered: status.now = Date.now() }
}
