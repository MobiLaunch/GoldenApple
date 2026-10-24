// A button: prominent, bordered, glass, plain, link or destructive; small,
// regular or large; tinted with the accent colour or any other.
import QtQuick
import "kit.js" as K
import "../theme"
import ".." as Lib

Box {
    id: root
    property string title: "Button"
    property string symbol: ""
    property string buttonStyle: "bordered"   // prominent | bordered | glass | plain | link | destructive
    property string size: "regular"           // small | regular | large
    property string tint: ""                  // "" is the app's accent colour
    property real buttonRadius: -1            // -1: a capsule
    property string fontFamily: ""
    property int fontWeight: 0
    tappable: true

    readonly property color tintColor: c(buttonStyle === "destructive" ? "red" : (tint || "accent"), "#0a84ff")
    readonly property real h: size === "small" ? 24 : size === "large" ? 40 : 30
    readonly property real hpad: size === "small" ? 10 : size === "large" ? 22 : 15
    readonly property real fsize: size === "small" ? 11 : size === "large" ? 15 : 13
    readonly property bool filled: buttonStyle === "prominent"
    readonly property color textColor: foreground ? foregroundColor
        : filled ? K.onColor(String(tintColor)) : buttonStyle === "glass" ? c("label") : tintColor
    contentWidth: buttonStyle === "link" ? row.implicitWidth : row.implicitWidth + 2 * hpad
    contentHeight: buttonStyle === "link" ? row.implicitHeight : h

    Rectangle {
        id: capsule
        anchors.fill: parent
        visible: root.buttonStyle !== "plain" && root.buttonStyle !== "link"
        radius: root.buttonRadius >= 0 ? root.buttonRadius : height / 2
        color: root.filled ? root.tintColor
             : root.buttonStyle === "glass" ? K.material("regular", root.kenv).tint
             : root.buttonStyle === "destructive" ? K.alpha(root.tintColor, root.dark ? 0.24 : 0.14)
             : (root.dark ? "#26ffffff" : "#12000000")
        border { width: root.buttonStyle === "glass" ? 1 : 0; color: K.material("regular", root.kenv).rim }
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: hover.hovered ? (root.filled ? "#1affffff" : (root.dark ? "#0fffffff" : "#0a000000")) : "transparent"
        }
    }
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Lib.Symbol {
            visible: !!root.symbol
            anchors.verticalCenter: parent.verticalCenter
            name: root.symbol
            size: root.fsize + 3
            tone: root.filled ? "white" : "accent"
            color: root.textColor
        }
        Text {
            visible: !!root.title
            anchors.verticalCenter: parent.verticalCenter
            text: root.title
            color: root.textColor
            font {
                family: K.fontFamily(root.fontFamily, root.kenv, Theme.fontUi)
                pixelSize: root.fsize
                weight: K.qtWeight(root.fontWeight || (root.filled ? 600 : 500))
                underline: root.buttonStyle === "link" && hover.hovered
            }
        }
    }
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
}
