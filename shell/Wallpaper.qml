// Desktop wallpaper, drawn by the shell on the background layer of each screen.
// The same GG_WALLPAPER image feeds the lock screen and the menu bar's
// light/dark sampling, so all three always agree.
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import "components"

PanelWindow {
    id: wall
    property string path: Prefs.wallpaper
    property real contextX: 0
    property real contextY: 0
    signal editWidgets()

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "gg-wallpaper"
    // Where it is, for the glass of a menu opened over it (see MenuPopup).
    DesktopBackdrop { surface: wall; namespace: "gg-wallpaper"; includeWindows: false }
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

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: mouse => {
            wall.contextX = mouse.x
            wall.contextY = mouse.y
            desktopMenu.open = true
        }
    }

    MenuPopup {
        id: desktopMenu
        anchor.window: wall
        anchor.rect.x: Math.min(wall.contextX, Math.max(0, wall.width - menuWidth - 8))
        anchor.rect.y: Math.min(wall.contextY, Math.max(0, wall.height - menuHeight - 8))
        items: [
            { label: "New Folder", action: () => Quickshell.execDetached(["sh", "-c", "d=$HOME/Desktop; mkdir -p \"$d\"; n=\"New Folder\"; p=\"$d/$n\"; i=2; while [ -e \"$p\" ]; do p=\"$d/$n $i\"; i=$((i+1)); done; mkdir \"$p\""]) },
            "-",
            { label: "Edit Widgets…", action: () => wall.editWidgets() },
            "-",
            { label: "Change Wallpaper…", action: () => Quickshell.execDetached(["gg-settings", "wallpaper"]) },
            { label: "Display Settings…", action: () => Quickshell.execDetached(["gg-settings", "display"]) }
        ]
    }
    HyprlandFocusGrab {
        windows: [desktopMenu]
        active: desktopMenu.open
        onCleared: desktopMenu.open = false
    }
}
