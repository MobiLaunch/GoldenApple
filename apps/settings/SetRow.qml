// One row in a Group: a title (and optional subtitle and icon) on the left, the
// control on the right, a hairline above unless it's the first. Clickable rows
// (`chevron`) open a sub-page, with a press highlight.
import QtQuick
import "../lib"
import "../lib/theme"

Item {
    id: row
    property string title
    property string subtitle
    property string symbol
    property string image              // an app's icon, in place of a symbol
    readonly property bool hasIcon: !!symbol || !!image
    property color symbolTint: "#8e8e93"
    property bool chevron: false
    property bool first: index === 0
    property int index: {
        const kids = parent ? parent.children : []
        for (let i = 0; i < kids.length; i++) if (kids[i] === row) return i
        return 0
    }
    default property alias trailing: slot.data
    signal clicked()
    width: parent ? parent.width : 500
    // As tall as its text (which wraps, and grows with Text Size) or its controls.
    height: Math.max(Theme.fh(subtitle ? 50 : 40), slot.childrenRect.height + 16, labels.implicitHeight + 18)

    Rectangle {
        visible: !row.first
        x: row.hasIcon ? 50 : 14; width: parent.width - x - 14; height: 0.5
        color: Theme.separator
    }
    Rectangle {
        anchors { fill: parent; margins: 3 }
        radius: 8
        color: Theme.dark ? "#ffffff" : "#000000"
        opacity: row.chevron ? (tap.pressed ? 0.08 : hover.hovered ? 0.04 : 0) : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }
    PaneIcon {
        visible: !!row.symbol && !row.image
        x: 14; anchors.verticalCenter: parent.verticalCenter
        symbol: row.symbol; tint: row.symbolTint
    }
    Image {
        visible: !!row.image
        x: 12; anchors.verticalCenter: parent.verticalCenter
        width: 28; height: 28
        sourceSize: Qt.size(56, 56)
        source: row.image
    }
    Column {
        id: labels
        x: row.hasIcon ? 50 : 14
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x - slot.width - 30
        Text {
            width: parent.width; elide: Text.ElideRight
            text: row.title
            color: Theme.label
            font { family: Theme.fontUi; pixelSize: Theme.fs(13) }
        }
        Text {
            visible: !!row.subtitle
            width: parent.width; wrapMode: Text.WordWrap
            text: row.subtitle
            color: Theme.secondaryLabel
            font { family: Theme.fontUi; pixelSize: Theme.fs(11) }
        }
    }
    Row {
        id: slot
        anchors { right: parent.right; rightMargin: row.chevron ? 32 : 14; verticalCenter: parent.verticalCenter }
        spacing: 8
    }
    Symbol {
        visible: row.chevron
        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
        name: "chevron-right"; tone: "gray"; size: 12
    }
    HoverHandler { id: hover; enabled: row.chevron }
    TapHandler { id: tap; enabled: row.chevron; onTapped: row.clicked() }
}
