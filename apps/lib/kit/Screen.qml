// One screen of an app: its content fills the window and scrolls when it's taller.
import QtQuick
import "kit.js" as K

Flickable {
    id: screen
    property var app: null
    readonly property var kenv: K.findEnv(parent)
    default property alias items: page.data
    readonly property Item contentContainer: page
    contentWidth: width
    contentHeight: Math.max(height, page.implicitHeight)
    boundsBehavior: Flickable.StopAtBounds
    clip: true
    Item {
        id: page
        readonly property string kitAxis: "screen"
        readonly property string kitAlign: "center"
        readonly property var kenv: screen.kenv
        width: screen.width
        height: screen.contentHeight
        implicitHeight: { let m = 0; for (const c of children) m = Math.max(m, c.implicitHeight); return m }
    }
}
