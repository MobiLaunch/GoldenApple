// A toolbar control: a glyph (or text, or both side by side) that highlights on
// hover, for use inside a ToolbarPill, or on its own as a round glass button
// (round: true).
import QtQuick
import "theme"

Item {
    id: button
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: button.text || button.symbol
    Accessible.checked: button.checked
    Accessible.onPressAction: button.activate()
    Keys.onSpacePressed: (event) => { if (!event.isAutoRepeat) button.activate() }
    Keys.onReturnPressed: button.activate()
    Keys.onEnterPressed: button.activate()
    FocusRing {}
    property string symbol
    property string text
    property bool checked: false
    property bool round: false
    property real symbolSize: Touch.enabled ? 19 : 17
    property string tone: "auto"
    property color glassColor: Theme.glassControl.tint
    signal clicked()
    property bool keyboardPressed: false
    function activate() {
        if (!enabled) return
        keyboardPressed = true
        keyRelease.restart()
        clicked()
    }
    Timer { id: keyRelease; interval: 90; onTriggered: button.keyboardPressed = false }
    readonly property bool both: !!symbol && !!text && !round

    implicitHeight: round ? 36 : 30
    implicitWidth: round ? 36 : Math.max(34, (label.visible ? label.implicitWidth + 20 : 0) + (both ? symbolSize + 6 : 0))
    opacity: enabled ? 1 : 0.35
    scale: !Theme.reduceMotion && (tap.pressed || keyboardPressed) ? 0.965
        : !Theme.reduceMotion && hover.hovered && button.enabled ? 1.012 : 1
    Behavior on scale { enabled: !Theme.reduceMotion; NumberAnimation { duration: 85; easing.type: Easing.OutCubic } }

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
        role: "control"
        tint: button.glassColor
        pressed: tap.pressed || button.keyboardPressed
        hovered: hover.hovered && button.enabled
    }
    Rectangle {
        anchors.fill: parent
        visible: !button.round
        radius: height / 2
        color: Theme.dark ? "#ffffff" : "#000000"
        opacity: button.checked ? 0.12 : (tap.pressed || button.keyboardPressed) ? 0.1
            : hover.hovered && button.enabled ? 0.06 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 0 : 110 } }
    }
    Rectangle {
        anchors.fill: parent
        visible: button.round && button.checked
        radius: height / 2
        color: Theme.dark ? "#ffffff" : "#000000"
        opacity: 0.12
    }
    Symbol {
        anchors.centerIn: button.both ? undefined : parent
        anchors.verticalCenter: button.both ? parent.verticalCenter : undefined
        x: button.both ? 10 : 0
        scale: 1
        name: button.symbol
        tone: button.tone
        size: button.symbolSize
        visible: !!button.symbol
    }
    Text {
        id: label
        anchors.centerIn: button.both ? undefined : parent
        anchors.verticalCenter: button.both ? parent.verticalCenter : undefined
        x: button.both ? 10 + button.symbolSize + 6 : 0
        visible: !!button.text
        text: button.text
        color: Theme.label
        font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: Font.Medium }
    }
    HoverHandler { id: hover }
    TapHandler { id: tap; enabled: button.enabled; onTapped: { button.forceActiveFocus(); button.clicked() } }
}

