// Boxes on top of each other, the later ones in front, each placed by
// alignment (topLeading … bottomTrailing) unless it says otherwise.
import QtQuick

Box {
    id: zstack
    property string alignment: "center"
    default property alias items: layer.data
    readonly property Item contentContainer: layer   // where the App Designer adds children
    contentWidth: layer.implicitWidth
    contentHeight: layer.implicitHeight

    Item {
        id: layer
        readonly property string kitAxis: "z"
        readonly property string kitAlign: zstack.alignment
        readonly property var kenv: zstack.kenv
        width: zstack.innerWidth
        height: zstack.innerHeight
        implicitWidth: { let m = 0; for (const c of children) if (c.visible) m = Math.max(m, c.implicitWidth); return m }
        implicitHeight: { let m = 0; for (const c of children) if (c.visible) m = Math.max(m, c.implicitHeight); return m }
    }
}
