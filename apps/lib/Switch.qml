// A Liquid Glass switch, as on macOS 27: a capsule track (accent when on) and a
// white knob that, while held or dragged, turns into a clear glass lens and
// stretches. Click or drag to change; Space toggles it with focus.
import QtQuick
import "theme"

Item {
    id: sw
    property bool checked: false
    property bool enabled_: true
    signal toggled(bool checked)
    implicitWidth: 38; implicitHeight: 22
    opacity: enabled && enabled_ ? 1 : 0.4
    Accessible.role: Accessible.CheckBox
    Accessible.checkable: true
    Accessible.checked: checked
    Accessible.onPressAction: flip()
    FocusRing { visible: sw.activeFocus && sw.enabled && sw.enabled_ }
    activeFocusOnTab: enabled && enabled_

    function flip() { if (!enabled || !enabled_) return; checked = !checked; toggled(checked) }
    Keys.onSpacePressed: (event) => { if (!event.isAutoRepeat) flip() }

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: sw.checked ? Theme.accent : (Theme.dark ? "#3dffffff" : "#29000000")
        Behavior on color { ColorAnimation { duration: 175 } }
        border { width: sw.activeFocus ? 3 : 0; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45) }
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "#ffffff"
            opacity: ma.containsMouse && sw.enabled && sw.enabled_ ? 0.045 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 1 : 100 } }
        }
    }
    Glass {
        id: knob
        readonly property bool active: ma.pressed
        height: parent.height - 4 + (active ? 6 : 0)
        width: height + (active ? 10 : 0)
        radius: height / 2
        anchors.verticalCenter: parent.verticalCenter
        x: sw.checked ? parent.width - width - 2 + (active ? 3 : 0) : 2 - (active ? 3 : 0)
        filled: !active
        tint: Qt.rgba(1, 1, 1, 0.14)
        lens: 5
        Behavior on x { enabled: !Theme.reduceMotion; Spring { spring: Theme.snappy } }
        scale: !Theme.reduceMotion && ma.containsMouse && !ma.pressed ? 1.025 : 1
        Behavior on scale { enabled: !Theme.reduceMotion; NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
        Behavior on width { enabled: !Theme.reduceMotion; Spring { spring: Theme.snappy } }
        Behavior on height { enabled: !Theme.reduceMotion; Spring { spring: Theme.snappy } }
        // Shadow under the white knob
        shadow: knob.filled ? "#26000000" : "transparent"
    }
    MouseArea {
        id: ma
        enabled: sw.enabled && sw.enabled_
        anchors.fill: parent
        hoverEnabled: true
        property real startX
        property bool dragged: false
        onPressed: (m) => { sw.forceActiveFocus(); startX = m.x; dragged = false }
        onPositionChanged: (m) => {
            if (pressed && Math.abs(m.x - startX) > 6) {
                dragged = true
                const want = m.x > width / 2
                if (want !== sw.checked) { sw.checked = want; sw.toggled(want) }
            }
        }
        onReleased: if (!dragged) sw.flip()
    }
}

