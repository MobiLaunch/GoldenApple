// Desktop wallpaper, drawn by the shell on the background layer of each screen.
// The same GG_WALLPAPER image feeds the lock screen and the menu bar's
// light/dark sampling, so all three always agree.
import Quickshell
import Quickshell.Wayland
import QtQuick

PanelWindow {
    id: wall
    property string path: Quickshell.env("GG_WALLPAPER") || "/usr/share/backgrounds/golden-gate/tide.png"

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "gg-wallpaper"
    color: "#1b3f9e"   // the wallpaper's deep blue, shown until the image is decoded

    Image {
        anchors.fill: parent
        source: "file://" + wall.path
        sourceSize: Qt.size(wall.width, wall.height)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        opacity: status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
    }
}
