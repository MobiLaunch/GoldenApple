// A pop-up button (NSPopUpButton): the chosen option with ⌃⌄, opening a menu
// of the options with the chosen one ticked.
//   PopUpButton { options: ["Small", "Medium", "Large"]; current: 1; onPicked: (i) => … }
import QtQuick
import "theme"

Item {
    id: pop
    property var options: []
    property int current: 0
    property Item menuParent: null      // the window's overlay (AppWindow.overlay)
    signal picked(int index)
    implicitWidth: Math.max(90, label.implicitWidth + 44); implicitHeight: 24

    Glass {
        anchors.fill: parent
        radius: 7
        tint: Theme.dark ? "#4d5a5a5e" : "#f2ffffff"
        lens: 3
        pressed: ma.pressed
        hovered: ma.containsMouse
        Rectangle { z: -1; anchors { fill: parent; topMargin: 1; bottomMargin: -1 } radius: parent.radius; color: Theme.dark ? "#40000000" : "#14000000" }
    }
    Text {
        id: label
        x: 10; anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 36; elide: Text.ElideRight
        text: pop.options[pop.current] ?? ""
        color: Theme.label
        font { family: Theme.fontUi; pixelSize: 13 }
    }
    Symbol {
        anchors { right: parent.right; rightMargin: 7; verticalCenter: parent.verticalCenter }
        name: "chevron-updown"; tone: "auto"; size: 11; opacity: 0.8
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
            if (!pop.menuParent) return
            menu.popup(pop, 0, pop.height + 4, pop.options.map((o, i) => ({
                text: (i === pop.current ? "✓  " : "     ") + o,
                action: () => { pop.current = i; pop.picked(i) }
            })))
        }
    }
    PopupMenu { id: menu; parent: pop.menuParent ?? pop }
}
