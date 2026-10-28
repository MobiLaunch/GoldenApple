// An indeterminate progress indicator, the Mac's: twelve spokes, one bright
// one going round. With Reduce Motion the spokes stay put and the whole
// indicator breathes slowly instead.
//   Spinner { running: loading; label: "Loading messages" }
import QtQuick
import "theme"

Item {
    id: spinner
    property bool running: true
    property string label: "Loading"
    property real size: 18
    property color tone: Theme.secondaryLabel
    implicitWidth: size; implicitHeight: size
    visible: running
    Accessible.role: Accessible.ProgressBar
    Accessible.name: label
    Accessible.description: "In progress"

    property int lead: 0                    // the brightest spoke
    Timer {
        interval: 83                        // a turn a second
        repeat: true
        running: spinner.running && spinner.visible && !Theme.reduceMotion
        onTriggered: spinner.lead = (spinner.lead + 1) % 12
    }
    Repeater {
        model: 12
        Rectangle {
            required property int index
            width: Math.max(1.5, spinner.size * 0.09); height: spinner.size * 0.28
            radius: width / 2
            color: spinner.tone
            x: (spinner.width - width) / 2
            y: 0
            transform: Rotation { origin.x: width / 2; origin.y: spinner.height / 2; angle: index * 30 }
            // Spokes fade behind the lead one; held at an even mid-tone without motion.
            opacity: Theme.reduceMotion ? 0.55 : 0.18 + 0.82 * Math.pow(((index - spinner.lead + 12) % 12) / 11, 2)
        }
    }
    SequentialAnimation on opacity {
        running: spinner.running && spinner.visible && Theme.reduceMotion
        loops: Animation.Infinite
        NumberAnimation { to: 0.45; duration: Theme.motion.ambient.duration / 2; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: Theme.motion.ambient.duration / 2; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) spinner.opacity = 1
    }
}
