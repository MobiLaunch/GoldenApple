// The preview's stand-in for shell/macshell/MacShell.qml. MacShell needs
// Quickshell's Wayland, system tray, screencopy and shader modules, which the
// preview's stubs don't have, so the preview draws only CitronOS's surfaces.
// tests/shell-shots.sh (CI) loads the real MacShell under Quickshell.
import QtQuick

QtObject {
    property string ggWallpaper
    readonly property QtObject bar: QtObject {}
    readonly property QtObject dock: QtObject {}
    readonly property QtObject widgets: QtObject { property bool editing: false }
    readonly property QtObject clock: QtObject {}
}
