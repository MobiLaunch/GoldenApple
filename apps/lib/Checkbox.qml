// Shared CitronOS checkbox. Used by apps, Settings and Setup Assistant.
import QtQuick
import "theme"

Item {
    id: box
    activeFocusOnTab: true
    Accessible.role: Accessible.CheckBox
    Accessible.name: box.text
    Accessible.onPressAction: if (box.enabled) box.toggle()
    Keys.onSpacePressed: (event) => { if (!event.isAutoRepeat && box.enabled) box.toggle() }
    Keys.onReturnPressed: if (box.enabled) box.toggle()
    Keys.onEnterPressed: if (box.enabled) box.toggle()

    property bool checked: false
    property string text: ""
    property string detail: ""
    signal toggled(bool checked)

    opacity: enabled ? 1 : 0.45
    implicitWidth: Math.max(20, copy.implicitWidth + 24)
    implicitHeight: Math.max(20, copy.implicitHeight)
    height: implicitHeight

    function toggle() {
        if (!enabled) return
        checked = !checked
        toggled(checked)
    }

    FocusRing {}

    Rectangle {
        id: square
        y: 2
        width: 16
        height: 16
        radius: 4
        color: box.checked ? Theme.accent : (Theme.dark ? "#26ffffff" : "#ffffff")
        border.width: box.checked ? 0 : 1
        border.color: Theme.dark ? "#4dffffff" : "#40000000"
        scale: !Theme.reduceMotion && ma.pressed ? 0.94 : !Theme.reduceMotion && ma.containsMouse ? 1.025 : 1
        Behavior on scale { enabled: !Theme.reduceMotion; NumberAnimation { duration: 85; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: Theme.reduceMotion ? 1 : 110 } }

        Symbol {
            anchors.centerIn: parent
            visible: opacity > 0
            opacity: box.checked ? 1 : 0
            scale: box.checked || Theme.reduceMotion ? 1 : 0.65
            name: "checkmark"
            tone: "white"
            size: 12
            Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 1 : 90 } }
            Behavior on scale { enabled: !Theme.reduceMotion; NumberAnimation { duration: 100; easing.type: Easing.OutBack } }
        }
    }

    Column {
        id: copy
        x: 24
        width: Math.max(0, box.width - x)
        spacing: 3

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: box.text
            color: Theme.label
            font.family: Theme.fontUi
            font.pixelSize: 13
            font.weight: Font.Medium
        }

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            visible: box.detail.length > 0
            text: box.detail
            color: Theme.secondaryLabel
            font.family: Theme.fontUi
            font.pixelSize: 12
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
            box.forceActiveFocus()
            box.toggle()
        }
    }
}
