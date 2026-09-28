// A Liquid Glass slider, as on macOS 27: a thin track filled in the accent up to
// the value and a pill-shaped glass knob that lifts into a clear lens while
// dragged. Optional tick marks (`steps` > 0) snap the value.
import QtQuick
import "theme"

Item {
    id: sl
    property real value: 0.5          // 0..1
    property int steps: 0             // > 0: snap to this many intervals, with ticks
    signal moved(real value)
    implicitWidth: 200; implicitHeight: 22
    activeFocusOnTab: true

    function set(v) {
        v = Math.max(0, Math.min(1, v))
        if (steps > 0) v = Math.round(v * steps) / steps
        if (v !== value) { value = v; moved(v) }
    }
    Keys.onLeftPressed: set(value - (steps > 0 ? 1 / steps : 0.05))
    Keys.onRightPressed: set(value + (steps > 0 ? 1 / steps : 0.05))

    Rectangle {
        id: track
        x: knob.width / 2; width: parent.width - knob.width
        anchors.verticalCenter: parent.verticalCenter
        height: 4; radius: 2
        color: Theme.dark ? "#3dffffff" : "#1f000000"
        Rectangle { width: track.width * sl.value; height: parent.height; radius: 2; color: Theme.accent }
        Repeater {
            model: sl.steps > 0 ? sl.steps + 1 : 0
            delegate: Rectangle {
                required property int index
                x: track.width * index / sl.steps - 1; y: 7
                width: 2; height: 5; radius: 1
                color: Theme.dark ? "#59ffffff" : "#40000000"
            }
        }
    }
    Glass {
        id: knob
        readonly property bool active: ma.pressed
        width: active ? 34 : 24; height: active ? 22 : 16
        radius: height / 2
        anchors.verticalCenter: parent.verticalCenter
        x: (sl.width - 24) * sl.value + 12 - width / 2
        filled: !active
        tint: Qt.rgba(1, 1, 1, 0.14)
        lens: 5
        Behavior on width { Spring { spring: Theme.snappy } }
        Behavior on height { Spring { spring: Theme.snappy } }
        shadow: knob.filled ? "#33000000" : "transparent"
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        onPressed: (m) => { sl.forceActiveFocus(); sl.set((m.x - 12) / (width - 24)) }
        onPositionChanged: (m) => { if (pressed) sl.set((m.x - 12) / (width - 24)) }
    }
}
