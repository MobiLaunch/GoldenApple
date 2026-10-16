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

    readonly property real shownValue: Number.isFinite(value) ? Math.max(0, Math.min(1, value)) : 0
    readonly property real inset: Math.min(12, width / 2)
    readonly property real travel: Math.max(0, width - 2 * inset)
    opacity: enabled ? 1 : 0.45
    Accessible.role: Accessible.Slider
    Accessible.onIncreaseAction: set(value + (steps > 0 ? 1 / steps : 0.05))
    Accessible.onDecreaseAction: set(value - (steps > 0 ? 1 / steps : 0.05))
    FocusRing {}
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Home) { set(0); event.accepted = true }
        else if (event.key === Qt.Key_End) { set(1); event.accepted = true }
    }
    Keys.onUpPressed: set(value + (steps > 0 ? 1 / steps : 0.05))
    Keys.onDownPressed: set(value - (steps > 0 ? 1 / steps : 0.05))

    function set(v) {
        if (!enabled || !Number.isFinite(v)) return
        v = Math.max(0, Math.min(1, v))
        if (steps > 0) v = Math.round(v * steps) / steps
        if (v !== value) { value = v; moved(v) }
    }
    Keys.onLeftPressed: set(value - (steps > 0 ? 1 / steps : 0.05))
    Keys.onRightPressed: set(value + (steps > 0 ? 1 / steps : 0.05))

    Rectangle {
        id: track
        x: sl.inset; width: sl.travel
        anchors.verticalCenter: parent.verticalCenter
        height: ma.containsMouse && sl.enabled ? 5 : 4; radius: height / 2
        Behavior on height { enabled: !Theme.reduceMotion; NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
        color: Theme.dark ? "#3dffffff" : "#1f000000"
        Rectangle {
            width: track.width * sl.shownValue; height: parent.height
            radius: height / 2; color: Theme.accent
            Behavior on width {
                enabled: !Theme.reduceMotion && !ma.pressed
                NumberAnimation { duration: 105; easing.type: Easing.OutCubic }
            }
        }
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
        width: active ? 34 : ma.containsMouse ? 27 : 24
        height: active ? 22 : ma.containsMouse ? 18 : 16
        radius: height / 2
        anchors.verticalCenter: parent.verticalCenter
        x: sl.travel * sl.shownValue + sl.inset - width / 2
        filled: !active
        tint: Qt.rgba(1, 1, 1, 0.14)
        lens: 5
        Behavior on x { enabled: !Theme.reduceMotion && !ma.pressed; NumberAnimation { duration: 95; easing.type: Easing.OutCubic } }
        Behavior on width { enabled: !Theme.reduceMotion; Spring { spring: Theme.snappy } }
        Behavior on height { enabled: !Theme.reduceMotion; Spring { spring: Theme.snappy } }
        shadow: knob.filled ? "#33000000" : "transparent"
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        enabled: sl.enabled
        onPressed: (m) => { sl.forceActiveFocus(); sl.set((m.x - sl.inset) / sl.travel) }
        onPositionChanged: (m) => { if (pressed) sl.set((m.x - sl.inset) / sl.travel) }
    }
}

