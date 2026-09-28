// A toolbar control: a glyph (or text) that highlights on hover, for use inside a
// ToolbarPill, or on its own as a round glass button (round: true).
import QtQuick
import "theme"

Item {
    id: button
    property string symbol
    property string text
    property bool checked: false
    property bool round: false
    property real symbolSize: 17
    property string tone: "auto"
    property color glassColor: Theme.dark ? "#eb3a3a3e" : "#ebffffff"
    signal clicked()

    implicitHeight: round ? 36 : 30
    implicitWidth: round ? 36 : Math.max(34, (label.visible ? label.implicitWidth + 20 : 0))
    opacity: enabled ? 1 : 0.35

    // Round buttons carry their own glass; pill buttons share the pill's.
    Rectangle {
        anchors.fill: parent
        radius: height / 2
        visible: button.round
        color: button.glassColor
        border { width: 0.5; color: Theme.dark ? "#26ffffff" : "#14000000" }
    }
    Rectangle {
        anchors.fill: parent
        anchors.margins: button.round ? 0 : 0
        radius: height / 2
        color: Theme.dark ? "#ffffff" : "#000000"
        opacity: button.checked ? 0.12 : hover.hovered && button.enabled ? 0.06 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }
    Symbol {
        anchors.centerIn: parent
        name: button.symbol
        tone: button.tone
        size: button.symbolSize
        visible: !!button.symbol
    }
    Text {
        id: label
        anchors.centerIn: parent
        visible: !!button.text
        text: button.text
        color: Theme.label
        font { family: Theme.fontUi; pixelSize: 13; weight: Font.Medium }
    }
    HoverHandler { id: hover }
    TapHandler { onTapped: button.clicked() }
}
