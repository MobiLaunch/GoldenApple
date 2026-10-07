// A push button in Liquid Glass: a capsule of glass, or the accent colour for
// the default button (`prominent`). Presses squash it; hover lifts it.
import QtQuick
import "theme"

Item {
    id: b
    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: b.text
    Accessible.onPressAction: if (b.enabled) { b.clicked() }
    Keys.onSpacePressed: (event) => { if (!event.isAutoRepeat && b.enabled) { b.clicked() } }
    Keys.onReturnPressed: if (b.enabled) { b.clicked() }
    Keys.onEnterPressed: if (b.enabled) { b.clicked() }
    FocusRing {}
    property string text
    property string symbol
    property bool prominent: false
    property bool destructive: false
    // Destructive wins: a prominent destructive button (Erase, Delete) is red,
    // never the accent blue that says "safe default".
    readonly property color red: Theme.dark ? "#ff453a" : "#ff3b30"
    signal clicked()
    implicitWidth: Math.max(72, row.implicitWidth + 28); implicitHeight: Theme.fh(26)
    opacity: enabled ? 1 : 0.45

    Glass {
        anchors.fill: parent
        radius: height / 2
        role: "control"
        // The default button is stained with the accent (red if it destroys
        // something); the others are plain glass.
        tint: b.prominent ? (b.destructive ? b.red : Theme.accent) : material.tint
        pressed: ma.pressed
        hovered: ma.containsMouse
        shadow: Theme.dark ? "#40000000" : "#1a000000"
    }
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
        scale: ma.pressed && !Theme.reduceMotion ? 0.975 : 1
        Behavior on scale { enabled: !Theme.reduceMotion; NumberAnimation { duration: 85; easing.type: Easing.OutCubic } }
        Symbol { visible: !!b.symbol; anchors.verticalCenter: parent.verticalCenter; name: b.symbol; size: 14; tone: b.prominent ? "white" : "auto" }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: b.text
            color: b.prominent ? "#ffffff" : b.destructive ? b.red : Theme.label
            font { family: Theme.fontUi; pixelSize: Theme.fs(13); weight: b.prominent ? Font.DemiBold : Font.Medium }
        }
    }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; enabled: b.enabled; onClicked: { b.forceActiveFocus(); b.clicked() } }
}

