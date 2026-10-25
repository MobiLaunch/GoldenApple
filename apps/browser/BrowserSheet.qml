// A panel Web puts over the page (Settings, Passwords, Website Permissions,
// Tab Groups …): centred, in the sheet colour with a soft shadow, and never
// just switched on: it grows in and fades as `reveal` turns on, and fades out.
import QtQuick
import "../lib"
import "../lib/theme"
import "theme"

Rectangle {
    id: sheet
    property bool reveal: false
    visible: reveal || opacity > 0.01
    opacity: reveal ? 1 : 0
    scale: reveal || Theme.reduceMotion ? 1 : 0.94
    transformOrigin: Item.Center
    Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 1 : Theme.motion.fade; easing.type: Easing.OutCubic } }
    Behavior on scale { enabled: !Theme.reduceMotion; Spring { spring: Theme.popover } }
    anchors.centerIn: parent
    radius: Theme.radius.window
    color: WebColors.sheet
    border { width: 0.5; color: Theme.separator }

    Rectangle {
        z: -1
        anchors { fill: parent; margins: -14 }
        radius: sheet.radius + 8
        color: WebColors.shadow
        opacity: 0.24
    }
}
