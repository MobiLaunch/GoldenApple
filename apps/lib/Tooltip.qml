// A help tag: put it inside the item it explains.
//   ToolbarButton { symbol: "trash"; Tooltip { text: "Move to Trash" } }
// It appears after the pointer rests on its parent (`delay`), above it, or
// below when there's no room; it goes on a press or when the pointer leaves.
// Keyboard focus on the parent shows it too. It fades, with Reduce Motion
// at once. The parent's Accessible.description is set from it if it has none.
import QtQuick
import "theme"

Item {
    id: tip
    property string text
    property int delay: 600
    property bool enabled: true
    readonly property bool shown: bubble.opacity > 0.5
    anchors.fill: parent
    z: 1000

    property bool resting: false
    readonly property bool wanted: enabled && !!text && (resting || (parent?.activeFocus ?? false)) && !hover.pressed
    Component.onCompleted: if (parent && !parent.Accessible.description) parent.Accessible.description = Qt.binding(() => tip.text)

    HoverHandler {
        id: hover
        property bool pressed: false
        onHoveredChanged: {
            if (hovered) dwell.restart()
            else { dwell.stop(); tip.resting = false; pressed = false }
        }
    }
    // A press hides it (and it stays hidden until the pointer leaves).
    TapHandler {
        gesturePolicy: TapHandler.DragThreshold
        grabPermissions: PointerHandler.TakeOverForbidden
        onPressedChanged: if (pressed) { hover.pressed = true; tip.resting = false }
    }
    Timer { id: dwell; interval: tip.delay; onTriggered: tip.resting = true }

    Rectangle {
        id: bubble
        objectName: "tooltipBubble"
        readonly property real room: tip.mapToItem(null, 0, 0).y
        readonly property bool below: room < height + 8
        width: Math.min(label.implicitWidth + 16, 320)
        height: label.implicitHeight + 8
        x: Math.round((tip.width - width) / 2)
        y: below ? tip.height + 6 : -height - 6
        radius: Theme.radius.field
        color: Theme.windowBg
        border { width: 0.5; color: Theme.separator }
        opacity: tip.wanted ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 0 : (tip.wanted ? Theme.motion.tap.ms / 2 : Theme.motion.tap.ms / 3) } }
        Accessible.role: Accessible.ToolTip
        Accessible.name: tip.text
        Text {
            id: label
            anchors.centerIn: parent
            width: Math.min(implicitWidth, 304)
            text: tip.text
            wrapMode: Text.Wrap
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: Theme.font.callout.pixelSize }
        }
    }
}
