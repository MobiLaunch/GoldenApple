// A hairline between boxes: across a column, or down a row.
import QtQuick
import QtQuick.Layouts
import "kit.js" as K
import "../theme"

Item {
    id: divider
    property string color: "separator"
    property real thickness: 1
    property real inset: 0
    readonly property string axis: parent && parent.kitAxis !== undefined ? parent.kitAxis : "v"
    readonly property var kenv: K.findEnv(parent) || ({ dark: Theme.dark })
    readonly property bool across: axis !== "h"
    implicitWidth: across ? 0 : thickness
    implicitHeight: across ? thickness : 0
    Layout.fillWidth: across
    Layout.fillHeight: !across
    Rectangle {
        x: divider.across ? divider.inset : 0
        y: divider.across ? 0 : divider.inset
        width: divider.across ? Math.max(0, parent.width - 2 * divider.inset) : divider.thickness
        height: divider.across ? divider.thickness : Math.max(0, parent.height - 2 * divider.inset)
        color: K.color(divider.color, divider.kenv, "#22000000")
    }
}
