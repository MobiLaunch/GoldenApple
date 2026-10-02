// Close, minimise and zoom, glossy as on macOS 27. The glyphs show while the
// pointer is over the group; an inactive window shows them grey.
//   close: quits the app. minimise: moves the window to Hyprland's minimised
//   space (the Dock brings it back). zoom: fills the screen.
import Quickshell
import Quickshell.Hyprland
import QtQuick
import QtQuick.Shapes
import "theme"

Row {
    id: lights
    property bool active: true
    property bool canZoom: true
    readonly property bool showGlyphs: hover.hovered
    spacing: 8

    HoverHandler { id: hover }

    Repeater {
        model: [
            { kind: "close", color: "#ff5f57" },
            { kind: "minimize", color: "#febc2e" },
            { kind: "zoom", color: "#28c840" },
        ]
        delegate: Rectangle {
            id: light
            required property var modelData
            readonly property bool enabled_: modelData.kind !== "zoom" || lights.canZoom
            width: 13; height: 13; radius: 6.5
            color: (lights.active || lights.showGlyphs) && enabled_ ? modelData.color : (Theme.dark ? "#4a4a4d" : "#d4d4d4")
            scale: !Theme.reduceMotion && tap.pressed ? 0.88 : !Theme.reduceMotion && lights.showGlyphs ? 1.025 : 1
            Behavior on color { ColorAnimation { duration: Theme.reduceMotion ? 1 : 120 } }
            Behavior on scale { NumberAnimation { duration: Theme.reduceMotion ? 1 : 85; easing.type: Easing.OutCubic } }
            border { width: 0.5; color: Qt.rgba(0, 0, 0, 0.16) }
            // The gloss: a soft light catch across the top half.
            Rectangle {
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 1.5 }
                height: parent.height * 0.5
                radius: height / 2
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.55) }
                    GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
                }
            }
            Shape {
                anchors.fill: parent
                visible: opacity > 0
                opacity: lights.showGlyphs && light.enabled_ ? 1 : 0
                scale: lights.showGlyphs && !Theme.reduceMotion ? 1 : 0.82
                Behavior on opacity { NumberAnimation { duration: Theme.reduceMotion ? 1 : 90 } }
                Behavior on scale { NumberAnimation { duration: Theme.reduceMotion ? 1 : 100; easing.type: Easing.OutCubic } }
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: Qt.rgba(0, 0, 0, 0.55); strokeWidth: 1.2; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                    PathSvg {
                        path: light.modelData.kind === "close" ? "M4.3 4.3 L8.7 8.7 M8.7 4.3 L4.3 8.7"
                            : light.modelData.kind === "minimize" ? "M3.8 6.5 L9.2 6.5" : ""
                    }
                }
                ShapePath {   // zoom: two arrow heads pointing apart
                    strokeColor: "transparent"; fillColor: light.modelData.kind === "zoom" ? Qt.rgba(0, 0, 0, 0.55) : "transparent"
                    PathSvg { path: "M3.8 3.8 L7.6 3.8 L3.8 7.6 Z M9.2 9.2 L5.4 9.2 L9.2 5.4 Z" }
                }
            }
            TapHandler {
                id: tap
                enabled: light.enabled_
                onTapped: {
                    if (light.modelData.kind === "close") Qt.quit()
                    else if (light.modelData.kind === "minimize") Hyprland.dispatch("movetoworkspacesilent special:minimized")
                    else Hyprland.dispatch("fullscreen 1")
                }
            }
        }
    }
}
