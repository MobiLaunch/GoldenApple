// Empty space that grows to push its neighbours apart.
import QtQuick
import "kit.js" as K
import QtQuick.Layouts

Item {
    id: spacer
    property real minLength: 0
    readonly property string axis: parent && parent.kitAxis !== undefined ? parent.kitAxis : ""
    readonly property var kenv: K.findEnv(parent)
    implicitWidth: axis === "h" ? minLength : 0
    implicitHeight: axis === "v" ? minLength : 0
    Layout.fillWidth: axis === "h"
    Layout.fillHeight: axis === "v"
    Layout.minimumWidth: axis === "h" ? minLength : 0
    Layout.minimumHeight: axis === "v" ? minLength : 0
}
