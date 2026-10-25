// The "no" shake, as macOS shakes a password field: a few swings of
// target's property (x by default) dying away to 0, and, if flashProperty is
// set, that property rising to 1 and fading back (a red flush through the
// glass, say). Use: Shake { id: shake; target: field; property: "shakeX" }
// and shake.restart().
import QtQuick

ParallelAnimation {
    id: root
    property QtObject target
    property string property: "x"
    property real amplitude: 16
    property string flashProperty: ""
    property real unused: 0             // what the flash moves when there's none

    SequentialAnimation {
        NumberAnimation { target: root.target; property: root.property; to: -root.amplitude; duration: 45; easing.type: Easing.OutSine }
        NumberAnimation { target: root.target; property: root.property; to: root.amplitude * 0.875; duration: 70; easing.type: Easing.InOutSine }
        NumberAnimation { target: root.target; property: root.property; to: -root.amplitude * 0.6875; duration: 70; easing.type: Easing.InOutSine }
        NumberAnimation { target: root.target; property: root.property; to: root.amplitude * 0.5; duration: 70; easing.type: Easing.InOutSine }
        NumberAnimation { target: root.target; property: root.property; to: -root.amplitude * 0.25; duration: 70; easing.type: Easing.InOutSine }
        NumberAnimation { target: root.target; property: root.property; to: 0; duration: 80; easing.type: Easing.OutSine }
    }
    SequentialAnimation {
        NumberAnimation { target: root.flashProperty ? root.target : root; property: root.flashProperty || "unused"; to: 1; duration: 90 }
        NumberAnimation { target: root.flashProperty ? root.target : root; property: root.flashProperty || "unused"; to: 0; duration: 610; easing.type: Easing.OutCubic }
    }
}
