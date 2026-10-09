// Shared navigation row for CitronOS sidebars.
import QtQuick
import "theme"

Item {
    id: row
    property string text: ""
    property string symbol: ""
    property bool selected: false
    property string badge: ""
    property string symbolTone: "accent"
    property string selectedSymbolTone: symbolTone
    property color symbolColor: "transparent"
    property color selectedSymbolColor: symbolColor
    property Component leading: null
    property real leadingSize: 22
    property real indent: 0                 // outline levels (a project tree)
    property color selectedFill: Theme.selection
    property color selectedTextColor: Theme.label
    signal clicked()

    implicitHeight: Theme.fh(31)
    implicitWidth: 180
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: text
    Accessible.selected: row.selected
    Accessible.onPressAction: if (row.enabled) row.clicked()
    Keys.onSpacePressed: (event) => { if (!event.isAutoRepeat && row.enabled) clicked() }
    Keys.onReturnPressed: if (row.enabled) clicked()
    Keys.onEnterPressed: if (row.enabled) clicked()

    Rectangle {
        anchors { fill: parent; leftMargin: 2; rightMargin: 2 }
        radius: 7
        color: row.selected
            ? row.selectedFill
            : hover.hovered
                ? (Theme.dark ? "#12ffffff" : "#0a000000")
                : "transparent"
        scale: !Theme.reduceMotion && tap.pressed ? 0.985 : 1
        Behavior on scale { enabled: !Theme.reduceMotion; NumberAnimation { duration: 95; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: Theme.reduceMotion ? 0 : 105 } }
    }

    Loader {
        id: leadingLoader
        visible: row.leading !== null
        active: visible
        sourceComponent: row.leading
        x: 8 + row.indent
        anchors.verticalCenter: parent.verticalCenter
        width: row.leadingSize
        height: row.leadingSize
        scale: !Theme.reduceMotion && tap.pressed ? 0.94 : 1
        Behavior on scale { NumberAnimation { duration: Theme.reduceMotion ? 1 : 70; easing.type: Easing.OutCubic } }
    }

    Symbol {
        id: icon
        visible: row.leading === null && !!row.symbol
        x: 10 + row.indent
        anchors.verticalCenter: parent.verticalCenter
        name: row.symbol
        size: 16
        tone: row.selected ? row.selectedSymbolTone : row.symbolTone
        color: row.selected ? row.selectedSymbolColor : row.symbolColor
        scale: !Theme.reduceMotion && tap.pressed ? 0.92 : !Theme.reduceMotion && row.selected ? 1.05 : 1
        Behavior on scale { NumberAnimation { duration: Theme.reduceMotion ? 1 : 70; easing.type: Easing.OutCubic } }
    }

    Text {
        x: row.indent + (row.leading !== null ? 8 + row.leadingSize + 8 : row.symbol ? 36 : 12)
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x - (row.badge ? 42 : 10)
        text: row.text
        elide: Text.ElideRight
        color: row.selected ? row.selectedTextColor : Theme.label
        font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: row.selected ? Font.DemiBold : Font.Normal }
    }

    Rectangle {
        visible: !!row.badge
        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
        width: Math.max(18, badgeText.implicitWidth + 10)
        height: 18
        radius: 9
        color: Theme.accent
        Text {
            id: badgeText
            anchors.centerIn: parent
            text: row.badge
            color: "#ffffff"
            font { family: Theme.fontUi; pixelSize: Theme.fs(10); weight: Font.DemiBold }
        }
    }

    HoverHandler { id: hover; enabled: row.enabled }
    TapHandler { id: tap; enabled: row.enabled; onTapped: { row.forceActiveFocus(); row.clicked() } }
}
