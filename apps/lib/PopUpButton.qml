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
    activeFocusOnTab: true
    opacity: enabled ? 1 : 0.45
    Accessible.role: Accessible.ComboBox
    Accessible.name: options[current] ?? ""
    Accessible.onPressAction: openMenu()
    Keys.onSpacePressed: openMenu()
    Keys.onReturnPressed: openMenu()
    Keys.onEnterPressed: openMenu()
    Keys.onDownPressed: openMenu()
    FocusRing {}
    function openMenu() {
        if (!enabled || !menuParent || !options.length) return
        forceActiveFocus()
        menu.popup(pop, 0, pop.height + 4, options.map((o, i) => ({
            text: (i === current ? "✓  " : "     ") + o,
            action: () => { pop.current = i; pop.picked(i) }
        })), current)
    }
    implicitWidth: Math.max(90, label.implicitWidth + 44); implicitHeight: 24

    Glass {
        anchors.fill: parent
        radius: 7
        tint: Theme.dark ? "#4d5a5a5e" : "#f2ffffff"
        lens: 3
        pressed: ma.pressed
        hovered: ma.containsMouse
        shadow: Theme.dark ? "#40000000" : "#14000000"
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
        onClicked: pop.openMenu()
    }
    PopupMenu { id: menu; parent: pop.menuParent ?? pop; menuWidth: Math.max(220, pop.width) }
}

