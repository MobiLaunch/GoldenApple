// Shared navigation row for Golden Gate sidebars.
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
    property color selectedFill: Theme.selection
    property color selectedTextColor: Theme.label
    signal clicked()

    implicitHeight: 31
    implicitWidth: 180
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: text
    Keys.onSpacePressed: clicked()
    Keys.onReturnPressed: clicked()

    Rectangle {
        anchors { fill: parent; leftMargin: 2; rightMargin: 2 }
        radius: 7
        color: row.selected
            ? row.selectedFill
            : hover.hovered
                ? (Theme.dark ? "#12ffffff" : "#0a000000")
                : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.reduceMotion ? 1 : 90 } }
    }

    Loader {
        id: leadingLoader
        visible: row.leading !== null
        active: visible
        sourceComponent: row.leading
        x: 8
        anchors.verticalCenter: parent.verticalCenter
        width: row.leadingSize
        height: row.leadingSize
        scale: !Theme.reduceMotion && tap.pressed ? 0.94 : 1
        Behavior on scale { NumberAnimation { duration: Theme.reduceMotion ? 1 : 70; easing.type: Easing.OutCubic } }
    }

    Symbol {
        id: icon
        visible: row.leading === null && !!row.symbol
        x: 10
        anchors.verticalCenter: parent.verticalCenter
        name: row.symbol
        size: 16
        tone: row.selected ? row.selectedSymbolTone : row.symbolTone
        color: row.selected ? row.selectedSymbolColor : row.symbolColor
        scale: !Theme.reduceMotion && tap.pressed ? 0.92 : 1
        Behavior on scale { NumberAnimation { duration: Theme.reduceMotion ? 1 : 70; easing.type: Easing.OutCubic } }
    }

    Text {
        x: row.leading !== null ? 38 : row.symbol ? 36 : 12
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x - (row.badge ? 42 : 10)
        text: row.text
        elide: Text.ElideRight
        color: row.selected ? row.selectedTextColor : Theme.label
        font { family: Theme.fontUi; pixelSize: 13; weight: row.selected ? Font.DemiBold : Font.Normal }
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
            font { family: Theme.fontUi; pixelSize: 10; weight: Font.DemiBold }
        }
    }

    HoverHandler { id: hover }
    TapHandler { id: tap; onTapped: { row.forceActiveFocus(); row.clicked() } }
}
