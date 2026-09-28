// A sidebar row: symbol and label; the selected one sits on a grey pill in red.
import QtQuick
import "../lib"
import "../lib/theme"

Item {
    id: item
    property string symbol
    property string text
    property bool selected: false
    signal clicked()
    width: parent ? parent.width : 180
    height: 28

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: Theme.dark ? "#ffffff" : "#000000"
        opacity: item.selected ? (Theme.dark ? 0.12 : 0.07) : hover.hovered ? 0.04 : 0
    }
    Symbol {
        x: 10; anchors.verticalCenter: parent.verticalCenter
        name: item.symbol
        tone: item.selected ? "red" : "auto"
        size: 16
    }
    Text {
        x: 36; anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 42
        elide: Text.ElideRight
        text: item.text
        color: item.selected ? "#fa2d48" : Theme.label
        font { family: Theme.fontUi; pixelSize: 13 }
    }
    HoverHandler { id: hover }
    TapHandler { onTapped: item.clicked() }
}
