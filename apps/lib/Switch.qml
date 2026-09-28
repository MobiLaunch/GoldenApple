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
    opacity: enabled_ ? 1 : 0.4
    activeFocusOnTab: true

    function flip() { if (!enabled_) return; checked = !checked; toggled(checked) }
    Keys.onSpacePressed: flip()

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: sw.checked ? Theme.accent : (Theme.dark ? "#3dffffff" : "#29000000")
        Behavior on color { ColorAnimation { duration: 200 } }
        border { width: sw.activeFocus ? 3 : 0; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45) }
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
        Behavior on x { Spring { spring: Theme.bouncy } }
        Behavior on width { Spring { spring: Theme.snappy } }
        Behavior on height { Spring { spring: Theme.snappy } }
        // Shadow under the white knob
        Rectangle { z: -1; anchors { fill: parent; topMargin: 1; bottomMargin: -1 } radius: parent.radius; color: "#26000000"; visible: knob.filled }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        property real startX
        property bool dragged: false
        onPressed: (m) => { startX = m.x; dragged = false }
        onPositionChanged: (m) => {
            if (Math.abs(m.x - startX) > 6) {
                dragged = true
                const want = m.x > width / 2
                if (want !== sw.checked) { sw.checked = want; sw.toggled(want) }
            }
        }
        onReleased: if (!dragged) sw.flip()
    }
}
