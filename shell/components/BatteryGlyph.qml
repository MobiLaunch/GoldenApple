// Native-sized animated battery for the menu bar.
// Uses the measured level; a charge pulse never fakes a higher percentage.
// The lightning bolt remains visible even at low charge, and disappears at full.
import QtQuick
import QtQuick.Shapes
import "../ui/theme"

Item {
    id: glyph
    objectName: "menuBatteryGlyph"
    property real level: 0
    property bool charging: false
    property bool full: false
    property color ink: "#ffffff"
    property bool reduceMotion: Theme.reduceMotion
    readonly property real fraction: Math.max(0, Math.min(1, level))
    readonly property bool activeCharge: charging && !full
    readonly property color fillColor: activeCharge ? "#30d158"
        : fraction <= 0.1 && !charging ? "#ff453a" : ink
    implicitWidth: 29
    implicitHeight: 15
    width: implicitWidth
    height: implicitHeight
    Accessible.role: Accessible.Indicator
    Accessible.name: full ? "Battery fully charged" : activeCharge
        ? "Battery charging, " + Math.round(fraction * 100) + " percent"
        : "Battery, " + Math.round(fraction * 100) + " percent"

    Rectangle {
        id: outline
        objectName: "batteryOutline"
        x: 0; y: 1.5; width: 25.5; height: 12
        radius: 3.6
        color: "transparent"
        border.width: 1.2
        border.color: Qt.rgba(glyph.ink.r, glyph.ink.g, glyph.ink.b, 0.54)
        clip: true
        Rectangle {
            id: chargeFill
            objectName: "batteryChargingFill"
            x: 2; y: 2
            height: parent.height - 4
            width: Math.max(glyph.fraction > 0 ? 1 : 0, (parent.width - 4) * glyph.fraction)
            radius: 2
            color: glyph.fillColor
            Behavior on width {
                enabled: !glyph.reduceMotion
                NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
            }
            SequentialAnimation on opacity {
                running: glyph.activeCharge && !glyph.reduceMotion
                loops: Animation.Infinite
                NumberAnimation { to: 0.76; duration: 1150; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 1150; easing.type: Easing.InOutSine }
                onRunningChanged: if (!running) chargeFill.opacity = 1
            }
        }
        Shape {
            id: bolt
            objectName: "batteryBolt"
            visible: glyph.activeCharge
            x: 7.7; y: 0.2
            width: 10; height: 11.5
            opacity: glyph.activeCharge ? 1 : 0
            ShapePath {
                strokeColor: "transparent"
                fillColor: glyph.fraction >= 0.42 ? "#ffffff" : "#30d158"
                PathSvg { path: "M 6.2 0 L 1.1 6.5 H 4.7 L 3.6 11 L 9.3 4.3 H 5.8 Z" }
            }
        }
    }
    Rectangle {
        x: 26.2; y: 5.35
        width: 2; height: 4.2
        radius: 1.1
        color: Qt.rgba(glyph.ink.r, glyph.ink.g, glyph.ink.b, 0.54)
    }
}
