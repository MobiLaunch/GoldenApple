// Small visual-only squash and release bounce. The owner's geometry stays fixed.
import QtQuick
import "theme"

Item {
    id: feedback
    visible: false
    property bool pressed: false
    property real pulse: 1
    readonly property real xScale: Theme.reduceMotion ? 1 : (pressed ? 1.015 : 1) * pulse
    readonly property real yScale: Theme.reduceMotion ? 1 : (pressed ? 0.965 : 1) * pulse
    onPressedChanged: if (pressed) { bounce.stop(); pulse = 1 }
    function tap() {
        bounce.stop()
        if (Theme.reduceMotion || !enabled) { pulse = 1; return }
        pulse = 0.97
        bounce.start()
    }
    SequentialAnimation {
        id: bounce
        NumberAnimation { target: feedback; property: "pulse"; to: 1.025; duration: 95; easing.type: Easing.OutCubic }
        NumberAnimation { target: feedback; property: "pulse"; to: 1; duration: 240; easing.type: Easing.OutCubic }
    }
    onEnabledChanged: if (!enabled) { bounce.stop(); pulse = 1 }
    Connections {
        target: Theme
        function onReduceMotionChanged() { if (Theme.reduceMotion) { bounce.stop(); feedback.pulse = 1 } }
    }
}
