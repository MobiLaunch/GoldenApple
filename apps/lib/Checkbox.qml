// A Mac checkbox with its label; the box springs a little when ticked.
import QtQuick
import "theme"

Item {
    id: box
    activeFocusOnTab: true
    Accessible.role: Accessible.CheckBox
    Accessible.name: box.text
    Accessible.onPressAction: if (box.enabled) { box.toggle() }
    Keys.onSpacePressed: (event) => { if (!event.isAutoRepeat && box.enabled) { box.toggle() } }
    Keys.onReturnPressed: if (box.enabled) { box.toggle() }
    Keys.onEnterPressed: if (box.enabled) { box.toggle() }
    FocusRing {}
    property bool checked: false
    property string text
    signal toggled(bool checked)
    Accessible.checked: checked
    opacity: enabled ? 1 : 0.45
    function toggle() { if (!enabled) return; checked = !checked; toggled(checked) }
    implicitWidth: 20 + label.implicitWidth + 8; implicitHeight: 20

    Rectangle {
        id: square
        y: 2; width: 16; height: 16; radius: 4
        color: box.checked ? Theme.accent : (Theme.dark ? "#26ffffff" : "#ffffff")
        border { width: box.checked ? 0 : 1; color: Theme.dark ? "#4dffffff" : "#40000000" }
        scale: ma.pressed ? 0.88 : 1
        Behavior on scale { Spring { spring: Theme.bouncy } }
        Behavior on color { ColorAnimation { duration: 120 } }
        Symbol { anchors.centerIn: parent; visible: box.checked; name: "checkmark"; tone: "white"; size: 12 }
    }
    Text {
        id: label
        x: 24; anchors.verticalCenter: square.verticalCenter
        text: box.text
        color: Theme.label
        font { family: Theme.fontUi; pixelSize: 13 }
    }
    MouseArea { id: ma; anchors.fill: parent; onClicked: { box.forceActiveFocus(); box.toggle() } }
}

