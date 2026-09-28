// A number that follows `target` on a damped spring, parameterised like SwiftUI's
// .spring(response:dampingFraction:). Unlike a timed animation, changing the
// target mid-flight keeps the current velocity, so a retargeted motion bends
// toward the new goal instead of stopping and starting over (what makes iOS
// motion feel continuous).
//   SpringValue { id: x; response: 0.5; dampingFraction: 0.86 }   then set x.target
import QtQuick
import "../theme"

Item {
    id: spring
    visible: false

    property real target: 0
    property real value: 0
    property real velocity: 0
    property real response: 0.5          // seconds for one undamped oscillation
    property real dampingFraction: 0.86  // 1 = no overshoot
    property real epsilon: 0.1           // settle once this close and nearly still
    readonly property bool moving: frames.running

    // Put the value somewhere without animating.
    function jump(v) { frames.stop(); velocity = 0; value = v; target = v }

    onTargetChanged: {
        if (Theme.reduceMotion) jump(target)
        else if (Math.abs(target - value) > epsilon || Math.abs(velocity) > epsilon) frames.start()
    }
    Connections {
        target: Theme
        function onReduceMotionChanged() { if (Theme.reduceMotion) spring.jump(spring.target) }
    }

    FrameAnimation {
        id: frames
        onTriggered: {
            const w = 2 * Math.PI / Math.max(0.05, spring.response)
            const k = w * w, c = 2 * w * spring.dampingFraction
            const dt = Math.min(frameTime, 0.05)             // a stalled frame shouldn't fling it
            const steps = Math.max(1, Math.ceil(dt / 0.004))  // small steps keep stiff springs stable
            const h = dt / steps
            let x = spring.value, v = spring.velocity
            for (let i = 0; i < steps; i++) {
                v += (-k * (x - spring.target) - c * v) * h
                x += v * h
            }
            if (Math.abs(x - spring.target) < spring.epsilon && Math.abs(v) < spring.epsilon * 10) {
                spring.velocity = 0; spring.value = spring.target; stop()
            } else {
                spring.velocity = v; spring.value = x
            }
        }
    }
}

