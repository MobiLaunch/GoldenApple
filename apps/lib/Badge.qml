// A count on a red capsule: the Dock's unread badges, sidebar and tab counts.
// It pops in on a spring and bumps when the count goes up; with Reduce Motion
// it simply appears. Zero hides it.
//   Badge { count: unread; label: "unread messages" }
import QtQuick
import "theme"

Rectangle {
    id: badge
    property int count: 0
    property int max: 99                    // more shows as "99+"
    property string label: "new"            // read out after the count
    property real size: 18
    property color tone: Theme.accentRed
    readonly property string shownText: count > max ? max + "+" : String(count)

    implicitHeight: size
    implicitWidth: Math.max(size, text.implicitWidth + size * 0.6)
    radius: height / 2
    color: tone
    scale: count > 0 ? bump : 0
    visible: scale > 0.01
    Accessible.role: Accessible.StaticText
    Accessible.name: count > 0 ? shownText + " " + label : ""
    Accessible.ignored: count <= 0

    property real bump: 1
    Behavior on scale { enabled: !Theme.reduceMotion; Spring { spring: Theme.bouncy } }
    property int last: 0
    onCountChanged: {
        if (Theme.reduceMotion) { pulse.stop(); bump = 1 }
        else if (count > last && last > 0) pulse.restart()
        last = count
    }
    SequentialAnimation {
        id: pulse
        NumberAnimation { target: badge; property: "bump"; to: 1.28; duration: Theme.motion.tap.ms / 2; easing.type: Easing.OutQuad }
        NumberAnimation { target: badge; property: "bump"; to: 1; duration: Theme.motion.tap.ms; easing.type: Easing.OutBack }
    }
    Text {
        id: text
        anchors.centerIn: parent
        text: badge.shownText
        color: Theme.vibrant.label
        font { family: Theme.fontUi; pixelSize: Math.round(badge.size * 0.62); weight: Font.DemiBold }
    }
}
