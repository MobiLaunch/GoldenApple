// A toolbar control: a glyph (or text) that highlights on hover, for use inside a
// ToolbarPill, or on its own as a round glass button (round: true).
import QtQuick
import "theme"

Item {
    id: button
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: button.text || button.symbol
    Accessible.onPressAction: if (button.enabled) { button.clicked() }
    Keys.onSpacePressed: (event) => { if (!event.isAutoRepeat && button.enabled) { button.clicked() } }
    Keys.onReturnPressed: if (button.enabled) { button.clicked() }
    Keys.onEnterPressed: if (button.enabled) { button.clicked() }
    FocusRing {}
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
    scale: !Theme.reduceMotion && tap.pressed ? 0.965 : !Theme.reduceMotion && hover.hovered && button.enabled ? 1.018 : 1
    y: !Theme.reduceMotion && hover.hovered && button.enabled && !tap.pressed ? -0.5 : 0
    Behavior on scale { enabled: !Theme.reduceMotion; NumberAnimation { duration: 85; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: !Theme.reduceMotion; NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

    // Round buttons carry their own Liquid Glass; pill buttons share the pill's.
    Rectangle {
        anchors { fill: parent; topMargin: 2; bottomMargin: -2 }
        visible: button.round
        radius: height / 2
        color: Theme.dark ? "#40000000" : "#12000000"
    }
    Glass {
        anchors.fill: parent
        visible: button.round
        radius: height / 2
        tint: button.glassColor
        rimLow: Theme.dark ? "#1fffffff" : "#14000000"
        lens: 5
        pressed: tap.pressed
        hovered: hover.hovered && button.enabled
    }
    Rectangle {
        anchors.fill: parent
        visible: !button.round
        radius: height / 2
        color: Theme.dark ? "#ffffff" : "#000000"
        opacity: button.checked ? 0.12 : tap.pressed ? 0.1 : hover.hovered && button.enabled ? 0.06 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }
    Rectangle {
        anchors.fill: parent
        visible: button.round && button.checked
        radius: height / 2
        color: Theme.dark ? "#ffffff" : "#000000"
        opacity: 0.12
    }
    Symbol {
        anchors.centerIn: parent
        scale: 1
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
    TapHandler { id: tap; enabled: button.enabled; onTapped: { button.forceActiveFocus(); button.clicked() } }
}

