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
    signal clicked()
    implicitWidth: Math.max(72, row.implicitWidth + 28); implicitHeight: 26
    opacity: enabled ? 1 : 0.45

    Glass {
        anchors.fill: parent
        radius: height / 2
        tint: b.prominent ? Theme.accent : (Theme.dark ? "#4d5a5a5e" : "#f2ffffff")
        lens: 4
        pressed: ma.pressed
        hovered: ma.containsMouse
        shadow: Theme.dark ? "#40000000" : "#1a000000"
    }
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Symbol { visible: !!b.symbol; anchors.verticalCenter: parent.verticalCenter; name: b.symbol; size: 14; tone: b.prominent ? "white" : "auto" }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: b.text
            color: b.prominent ? "#ffffff" : b.destructive ? "#ff3b30" : Theme.label
            font { family: Theme.fontUi; pixelSize: 13; weight: b.prominent ? Font.DemiBold : Font.Medium }
        }
    }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; enabled: b.enabled; onClicked: { b.forceActiveFocus(); b.clicked() } }
}

