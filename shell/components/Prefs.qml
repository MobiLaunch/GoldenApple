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
    // Shell glass bends live captures of the windows under it (DesktopBackdrop);
    // off ("glassWindows": false), it bends only the wallpaper.
    readonly property bool glassWindows: data.glassWindows ?? true
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
    readonly property real textScale: data.textScale ?? 1
    readonly property bool alwaysShowScrollbars: data.scrollBars === "always"
    readonly property real glassSolidity: data.glassSolidity ?? 0
    // The menu bar's own background, as "Show menu bar background" in macOS 26.
    readonly property bool menuBarBackground: data.menuBar?.background ?? true
    readonly property bool clockShowDay: data.menuBar?.showDay ?? true
    readonly property bool clockShowDate: data.menuBar?.showDate ?? true
    readonly property bool clock24: data.menuBar?.clock24 ?? false
    readonly property bool clockSeconds: data.menuBar?.seconds ?? false
    // Control Center (Settings): what the menu bar shows, defaults as macOS's.
    readonly property var barItems: data.menuBar?.items ?? ({})
    readonly property bool barWifi: barItems.wifi ?? true
    readonly property bool barBluetooth: barItems.bluetooth ?? false
    readonly property bool barSound: barItems.sound ?? false
    readonly property bool barFocus: barItems.focus ?? true          // while a Focus is on
    readonly property bool barNowPlaying: barItems.nowPlaying ?? false
    readonly property bool barBattery: barItems.battery ?? true
    readonly property bool barBatteryPercent: barItems.batteryPercent ?? false
    readonly property bool barSpotlight: barItems.spotlight ?? true
    readonly property bool barCitron: barItems.citron ?? true
    // Notifications (Settings): previews, sounds, and each app's choices,
    // keyed as Notifications.keyOf() names an app.
    readonly property var notifyPrefs: data.notifications ?? ({})
    readonly property string notifyPreviews: notifyPrefs.previews ?? "always"   // always | never
    readonly property bool notifySounds: notifyPrefs.sounds ?? true
    function notifyApp(key) {
        return Object.assign({ allow: true, banners: true, sound: true, badges: true }, (notifyPrefs.apps ?? {})[key] ?? {})
    }
    // Spotlight (Settings): which kinds of result it shows.
    function spotlightShows(kind) { return (data.spotlight ?? {})[kind] ?? true }
    // Lock Screen (Settings): a message under the clock.
    readonly property string lockMessage: data.lockScreen?.message ?? ""
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
