// A pop-up menu of options.
import QtQuick
import "kit.js" as K
import "../theme"

Box {
    id: root
    property string label: ""
    property var options: ["First", "Second", "Third"]
    property int value: 0
    signal edited(int value)
    property int chosen: value
    onValueChanged: chosen = value
    contentWidth: (label ? labelText.implicitWidth + 10 : 0) + button.width
    contentHeight: 26

    Text {
        id: labelText
        visible: !!root.label
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        color: root.foregroundColor
        font { family: Theme.fontUi; pixelSize: 13 }
    }
    Rectangle {
        id: button
        x: root.label ? root.innerWidth - width : 0
        width: Math.max(90, current.implicitWidth + 40)
        height: 26
        radius: 7
        color: root.dark ? "#3a3a3c" : "#ffffff"
        border { width: 0.5; color: root.dark ? "#33ffffff" : "#2e000000" }
        Text {
            id: current
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            text: root.options.length ? String(root.options[Math.max(0, Math.min(root.options.length - 1, root.chosen))]) : ""
            color: root.c("label")
            font { family: Theme.fontUi; pixelSize: 13 }
        }
        Text {
            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            text: "⌃⌄"
            rotation: 0
            color: root.c("secondaryLabel")
            font.pixelSize: 9
        }
        TapHandler { onTapped: menu.open() }
    }

    // The menu opens on the Scope's overlay, above everything else.
    Item {
        id: menu
        parent: root.kenv && root.kenv.overlay ? root.kenv.overlay : root
        anchors.fill: parent
        visible: false
        function open() {
            const p = button.mapToItem(menu.parent, 0, button.height + 4)
            list.x = p.x; list.y = p.y
            visible = true
        }
        MouseArea { anchors.fill: parent; onClicked: menu.visible = false }
        Rectangle {
            id: list
            width: Math.max(button.width, 170)
            height: column.implicitHeight + 10
            radius: 10
            color: root.dark ? "#ee2c2c2e" : "#f8ffffff"
            border { width: 0.5; color: root.dark ? "#33ffffff" : "#26000000" }
            Column {
                id: column
                x: 5; y: 5
                width: list.width - 10
                Repeater {
                    model: root.options
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: column.width
                        height: 24
                        radius: 6
                        color: optHover.hovered ? root.c("accent") : "transparent"
                        Text {
                            x: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: (root.chosen === parent.index ? "✓  " : "    ") + String(parent.modelData)
                            color: optHover.hovered ? "white" : root.c("label")
                            font { family: Theme.fontUi; pixelSize: 13 }
                        }
                        HoverHandler { id: optHover }
                        TapHandler { onTapped: { root.chosen = parent.index; root.edited(parent.index); menu.visible = false } }
                    }
                }
            }
        }
    }
}
