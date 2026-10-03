// A sheet over the window, as on the Mac: the window dims and a glass panel
// drops from under the toolbar. Put it on the window's overlay layer:
//   Sheet { id: sheet; parent: win.overlay; panelWidth: 520; …content… }
//   sheet.open()
import QtQuick
import "../lib"
import "../lib/theme"

Item {
    id: sheet
    anchors.fill: parent
    visible: shown || fade.running
    z: 20

    property bool shown: false
    property real panelWidth: 480
    property real panelHeight: content.childrenRect.height + 40
    property bool dismissible: true
    default property alias content: content.data
    signal closed()

    function open() { shown = true; panel.forceActiveFocus() }
    function close() { if (shown) { shown = false; closed() } }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusWindow
        color: "#000000"
        opacity: sheet.shown ? (Theme.dark ? 0.32 : 0.14) : 0
        Behavior on opacity { NumberAnimation { id: fade; duration: Theme.reduceMotion ? 1 : 180 } }
        MouseArea {
            anchors.fill: parent
            onClicked: if (sheet.dismissible) sheet.close()
        }
    }

    Item {
        id: panel
        focus: true
        width: sheet.panelWidth
        height: sheet.panelHeight
        x: (parent.width - width) / 2
        y: Theme.sizeToolbar - 4 + (sheet.shown ? 0 : -24)
        opacity: sheet.shown ? 1 : 0
        scale: sheet.shown ? 1 : 0.97
        Behavior on y { NumberAnimation { duration: Theme.reduceMotion ? 1 : Theme.popover.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.popover.curve } }
        Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 1 : 160 } }
        Behavior on scale { NumberAnimation { duration: Theme.reduceMotion ? 1 : Theme.popover.duration; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.popover.curve } }
        Keys.onEscapePressed: if (sheet.dismissible) sheet.close()

        Glass {
            anchors.fill: parent
            radius: 22
            role: "menu"
        }
        MouseArea { anchors.fill: parent }   // clicks on the panel stay on it
        Item {
            id: content
            anchors { fill: parent; margins: 20 }
        }
    }
}
