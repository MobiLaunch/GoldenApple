// A value between minimum and maximum, in steps if you like.
import QtQuick
import "kit.js" as K
import "../theme"

Box {
    id: root
    property real value: 0.5
    property real minimum: 0
    property real maximum: 1
    property real step: 0                     // 0: continuous
    property string tint: ""
    property bool showValue: false
    signal edited(real value)
    property real shown: value                // follows value; moves at once while dragged
    onValueChanged: shown = value
    readonly property color tintColor: c(tint || "accent", "#0a84ff")
    readonly property real fraction: maximum > minimum ? Math.max(0, Math.min(1, (shown - minimum) / (maximum - minimum))) : 0
    contentWidth: 180 + (showValue ? valueText.implicitWidth + 10 : 0)
    contentHeight: 22

    function setFromX(x) {
        const f = Math.max(0, Math.min(1, (x - 10) / Math.max(1, track.width - 20)))
        let v = minimum + f * (maximum - minimum)
        if (step > 0) v = minimum + Math.round((v - minimum) / step) * step
        v = Math.max(minimum, Math.min(maximum, v))
        if (v !== shown) { shown = v; edited(v) }
    }

    Item {
        id: track
        width: root.innerWidth - (root.showValue ? valueText.implicitWidth + 10 : 0)
        height: parent.height
        Rectangle {
            x: 10; width: parent.width - 20; height: 4; radius: 2
            anchors.verticalCenter: parent.verticalCenter
            color: root.dark ? "#3a3a3c" : "#e3e3e8"
            Rectangle { width: parent.width * root.fraction; height: parent.height; radius: 2; color: root.tintColor }
        }
        Rectangle {
            width: 20; height: 20; radius: 10
            anchors.verticalCenter: parent.verticalCenter
            x: 10 + (parent.width - 20) * root.fraction - 10
            color: "white"
            border { width: 0.5; color: "#26000000" }
        }
        MouseArea {
            anchors.fill: parent
            onPressed: (m) => root.setFromX(m.x)
            onPositionChanged: (m) => { if (pressed) root.setFromX(m.x) }
        }
    }
    Text {
        id: valueText
        visible: root.showValue
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        text: K.str(root.shown)
        color: root.foregroundColor
        font { family: Theme.fontUi; pixelSize: 12; features: { "tnum": 1 } }
    }
}
