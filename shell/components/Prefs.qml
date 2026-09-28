pragma Singleton
// Desktop preferences set in Settings, from ~/.config/golden-gate/desktop.json
// (watched, so changes apply at once):
//   { "wallpaper": "/path.png",
//     "dock": { "size": 54, "magnification": true, "magnifiedSize": 86,
//               "indicators": true, "animateLaunch": true },
//     "glass": "clear" | "tinted", "reduceMotion": false, "reduceTransparency": false }
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: prefs
    readonly property string file: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/golden-gate/desktop.json"
    property var data: ({})

    readonly property string wallpaper: data.wallpaper || Quickshell.env("GG_WALLPAPER") || "/usr/share/backgrounds/golden-gate/tide.png"
    readonly property real dockSize: data.dock?.size ?? 54
    readonly property bool dockMagnification: data.dock?.magnification ?? true
    readonly property real dockMagnifiedSize: Math.max(dockSize, data.dock?.magnifiedSize ?? 86)
    readonly property bool dockIndicators: data.dock?.indicators ?? true
    readonly property bool animateLaunch: (data.dock?.animateLaunch ?? true) && !reduceMotion
    readonly property string glass: data.glass ?? "clear"
    readonly property bool reduceMotion: data.reduceMotion ?? false
    readonly property bool reduceTransparency: data.reduceTransparency ?? false

    FileView {
        path: prefs.file
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { prefs.data = JSON.parse(text()) } catch (e) { prefs.data = ({}) } }
        onLoadFailed: prefs.data = ({})
    }
}
