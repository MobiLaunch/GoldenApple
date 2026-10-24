// A Weather card: tinted glass with a small-caps header (symbol + title) and
// whatever the card shows below it.
import QtQuick
import "../lib"
import "../lib/theme"

Rectangle {
    id: card
    property string title
    property string symbol
    property color tint: "#40000000"
    default property alias content: body.data
    readonly property real headerHeight: title ? 30 : 0

    radius: 18
    color: tint
    border { width: 0.5; color: "#26ffffff" }

    Row {
        visible: !!card.title
        x: 12; y: 11
        spacing: 5
        Symbol {
            anchors.verticalCenter: parent.verticalCenter
            name: card.symbol; tone: "white"; size: 11
            opacity: 0.6
            visible: !!card.symbol
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: card.title.toUpperCase()
            color: "#99ffffff"
            font { family: Theme.fontUi; pixelSize: Theme.fs(11); weight: Font.DemiBold; letterSpacing: 0.2 }
        }
    }
    Item {
        id: body
        anchors { fill: parent; topMargin: card.headerHeight; leftMargin: 12; rightMargin: 12; bottomMargin: 10 }
    }
}
