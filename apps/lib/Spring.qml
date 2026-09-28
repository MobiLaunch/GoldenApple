// Spring-shaped NumberAnimation. The curve is the spring from design/tokens.json,
// pre-integrated into a Bézier spline by design/build.mjs, so the shell moves
// exactly like the reference prototype (CSS linear()) and the compositor.
//   Behavior on scale { Spring { spring: Theme.popover } }
import QtQuick
import "theme"

NumberAnimation {
    property QtObject spring: Theme.snappy
    duration: Theme.reduceMotion ? 0 : spring.duration
    easing.type: Easing.BezierSpline
    easing.bezierCurve: spring.curve
}

