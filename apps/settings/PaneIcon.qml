// A pane's icon: a white symbol on a rounded square of the pane's colour, with
// the soft gradient System Settings gives them.
import QtQuick
import "../lib"

Rectangle {
    id: icon
    property string symbol
    property color tint: "#8e8e93"
    property real size: 22
    width: size; height: size
    radius: size * 0.26
    gradient: Gradient {
        GradientStop { position: 0; color: Qt.lighter(icon.tint, 1.18) }
        GradientStop { position: 1; color: icon.tint }
    }
    border { width: 0.5; color: "#26000000" }
    // Colored Golden Gate sidebar icon with a small specular top edge, not
    // the heavy floating tile from older macOS Tahoe betas.
    Rectangle {
        x: icon.size * 0.13; y: icon.size * 0.08
        width: icon.size * 0.72; height: Math.max(1, icon.size * 0.14)
        radius: height / 2; color: "#68ffffff"
        opacity: 0.47
    }
    Symbol { anchors.centerIn: parent; name: icon.symbol; tone: "white"; size: icon.size * 0.62 }
}
