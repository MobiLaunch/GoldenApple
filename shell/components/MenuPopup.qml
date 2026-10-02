// Glass drop-down menu anchored under a menu-bar item.
//   items: [{ label, shortcut, action: function }, "-", ...]
import Quickshell
import QtQuick
import QtQuick.Layouts
import "../ui/theme"

PopupWindow {
    id: menu
    property var items: []
    property bool open: false
    signal dismissed()

    visible: open || fade.running
    color: "transparent"
    implicitWidth: 240
    implicitHeight: column.implicitHeight + 12

    Glass { variant: "clear";
        id: panel
        anchors.fill: parent
        radius: Theme.radiusMenu
        tint: Theme.dark ? "#b8282830" : "#c8f4f4f6"
        opacity: menu.open ? 1 : 0
        scale: menu.open ? 1 : 0.94
        transformOrigin: Item.TopLeft
        Behavior on opacity { NumberAnimation { id: fade; duration: menu.open ? Theme.popover.duration : 140 } }
        Behavior on scale { Spring { spring: Theme.popover } }

        ColumnLayout {
            id: column
            anchors { fill: parent; margins: 6 }
            spacing: 0
            Repeater {
                model: menu.items
                delegate: Loader {
                    required property var modelData
                    Layout.fillWidth: true
                    sourceComponent: modelData === "-" ? separator : row
                    Component {
                        id: separator
                        Rectangle { implicitHeight: 11; color: "transparent"
                            Rectangle { anchors.centerIn: parent; width: parent.width - 20; height: 1; color: Theme.separator } }
                    }
                    Component {
                        id: row
                        Rectangle {
                            implicitHeight: 26
                            radius: Theme.radiusMenuItem
                            color: hover.containsMouse ? Theme.accent : "transparent"
                            Behavior on color { ColorAnimation { duration: Prefs.reduceMotion ? 1 : 85 } }
                            RowLayout {
                                anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.label
                                    color: hover.containsMouse ? "#ffffff" : Theme.label
                                    font { family: Theme.fontUi; pixelSize: 13 }
                                }
                                Text {
                                    text: modelData.shortcut ?? ""
                                    color: hover.containsMouse ? "#ffffff" : Theme.secondaryLabel
                                    font { family: Theme.fontUi; pixelSize: 12 }
                                }
                            }
                            MouseArea {
                                id: hover
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: { menu.open = false; menu.dismissed(); modelData.action?.() }
                            }
                        }
                    }
                }
            }
        }
    }
}
