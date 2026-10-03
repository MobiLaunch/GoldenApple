// A row of a settings page, as on macOS: the label right-aligned in a column,
// the control beside it, and an optional note underneath.
import QtQuick
import "../../lib/theme"

Item {
    id: row
    property string label: ""
    property string detail: ""
    property real labelWidth: 180
    // The label lines up with the control's first line.
    property real labelHeight: slot.children.length && slot.children[0].height > 0 ? Math.min(28, slot.children[0].height) : 28
    default property alias control: slot.data
    width: parent ? parent.width : 400
    implicitHeight: Math.max(28, slot.childrenRect.height) + (detail ? note.implicitHeight + 4 : 0)

    Text {
        width: row.labelWidth
        height: row.labelHeight
        horizontalAlignment: Text.AlignRight
        verticalAlignment: Text.AlignVCenter
        text: row.label ? row.label + ":" : ""
        color: Theme.label
        font { family: Theme.fontUi; pixelSize: 13 }
    }
    Item {
        id: slot
        x: row.labelWidth + 12
        width: row.width - x
        height: Math.max(28, childrenRect.height)
    }
    Text {
        id: note
        visible: !!row.detail
        x: slot.x
        y: slot.height + 4
        width: Math.min(440, slot.width)
        wrapMode: Text.Wrap
        text: row.detail
        color: Theme.secondaryLabel
        font { family: Theme.fontUi; pixelSize: 11 }
    }
}
