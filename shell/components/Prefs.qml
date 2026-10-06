pragma Singleton
// Desktop preferences set in Settings, from ~/.config/golden-gate/desktop.json
// (watched, so changes apply at once):
//   { "wallpaper": "/path.png",
//     "dock": { "size": 54, "indicators": true, "animateLaunch": true, "pinned": ["org.goldengate.Files", …] },
//     "widgets": [{ "id": "clock-1", "kind": "clock", "size": "small", "col": 1, "row": 0 }, …],
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
    readonly property bool dockIndicators: data.dock?.indicators ?? true
    readonly property bool animateLaunch: (data.dock?.animateLaunch ?? true) && !reduceMotion
    readonly property var dockPinned: Array.isArray(data.dock?.pinned) ? data.dock.pinned : null   // null: the default set
    // The apps kept in the Dock, in order, and the set a new account starts with.
    readonly property var defaultDockPinned: [
        "org.goldengate.Files", "org.goldengate.Web", "org.goldengate.Mail", "org.goldengate.Messages", "org.goldengate.Maps",
        "org.goldengate.Photos", "org.goldengate.Music", "org.goldengate.Calendar", "org.goldengate.Notes",
        "org.goldengate.Weather", "org.goldengate.Software", "org.goldengate.Settings", "org.goldengate.Terminal"
    ]
    readonly property var keptInDock: dockPinned ?? defaultDockPinned
    // Changes the Dock at once, and saves it (gg-pref writes desktop.json).
    function setDockPinned(ids) {
        data = Object.assign({}, data, { dock: Object.assign({}, data.dock ?? {}, { pinned: ids }) })
        Quickshell.execDetached(["gg-pref", "dock.pinned", JSON.stringify(ids)])
    }
    // Desktop widgets, [{ id, kind, size, col, row }]; null: the default set.
    readonly property var widgets: Array.isArray(data.widgets) ? data.widgets : null
    function setWidgets(list) {
        data = Object.assign({}, data, { widgets: list })
        Quickshell.execDetached(["gg-pref", "widgets", JSON.stringify(list)])
    }
    readonly property string glass: data.glass ?? "clear"
    readonly property bool reduceMotion: data.reduceMotion ?? false
    readonly property bool reduceTransparency: data.reduceTransparency ?? false
    // The menu bar's own background, as "Show menu bar background" in macOS 26.
    readonly property bool menuBarBackground: data.menuBar?.background ?? true
    readonly property bool clockShowDay: data.menuBar?.showDay ?? true
    readonly property bool clockShowDate: data.menuBar?.showDate ?? true
    readonly property bool clock24: data.menuBar?.clock24 ?? false
    readonly property bool clockSeconds: data.menuBar?.seconds ?? false
    readonly property bool focusDnd: data.focus?.dnd ?? false
    readonly property bool nightShift: data.display?.nightShift ?? false
    readonly property int displayWarmth: data.display?.warmth ?? 4500
    readonly property real savedBrightness: data.display?.brightness ?? -1

    FileView {
        path: prefs.file
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { prefs.data = JSON.parse(text()) } catch (e) { prefs.data = ({}) } }
        onLoadFailed: prefs.data = ({})
    }
}
