pragma Singleton
// Desktop preferences set in Settings, from ~/.config/golden-gate/desktop.json
// (watched, so changes apply at once):
//   { "wallpaper": "/path.png", "tablet": { "enabled": false, "widgets": […] },
//     "notifications": { … }, "focus": { … },
//     "glass": "clear" | "tinted", "reduceMotion": false, "reduceTransparency": false }
// The Dock, menu bar and desktop widgets are MacShell's, with settings of their own.
import Quickshell
import Quickshell.Io
import QtQuick
import "../ui" as Shared
import "../ui/FocusPolicy.js" as FocusPolicy

Singleton {
    id: prefs
    readonly property string file: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/golden-gate/desktop.json"
    property var data: ({})

    readonly property string wallpaper: data.wallpaper || Quickshell.env("GG_WALLPAPER") || "/usr/share/backgrounds/golden-gate/tide.png"
    // Shell glass bends live captures of the windows under it (DesktopBackdrop);
    // off ("glassWindows": false), it bends only the wallpaper.
    readonly property bool glassWindows: data.glassWindows ?? true
    // Settings › Sound: the alert sound (CitronOS's own, ui/assets/sounds),
    // and the chime when power is connected.
    readonly property string alertSound: data.sound?.alert ?? "Crystal"
    readonly property bool chargingSound: data.sound?.charging ?? true
    function soundPath(name) { return decodeURIComponent(Qt.resolvedUrl("../ui/assets/sounds/" + name + ".wav").toString().replace("file://", "")) }
    // Tablet Mode changes presentation only. No tablet-only partition or
    // alternate desktop session; unplugging the keyboard does not lose apps.
    readonly property bool tabletMode: Quickshell.env("GG_TABLET_PREVIEW") === "1" || (data.tablet?.enabled ?? false)
    // Tablet Home Screen widgets are independent of desktop widgets. Their
    // order and sizes survive sign-out, rotation and mode switching.
    readonly property var tabletWidgets: Array.isArray(data.tablet?.widgets) ? data.tablet.widgets : null
    function setTabletWidgets(list) {
        data = Object.assign({}, data, {
            tablet: Object.assign({}, data.tablet ?? {}, { widgets: list })
        })
        Quickshell.execDetached(["gg-pref", "tablet.widgets", JSON.stringify(list)])
    }
    readonly property real dockSize: data.dock?.size ?? 54
    // The apps a new account starts with (the tablet Home Screen's Dock row).
    readonly property var defaultDockPinned: [
        "org.goldengate.Files", "org.goldengate.Web", "org.goldengate.Mail", "org.goldengate.Messages", "org.goldengate.Maps",
        "org.goldengate.Photos", "org.goldengate.Music", "org.goldengate.Calendar", "org.goldengate.Notes",
        "org.goldengate.Weather", "org.goldengate.Software", "org.goldengate.Settings", "org.goldengate.Terminal"
    ]
    readonly property string glass: data.glass ?? "clear"
    readonly property bool reduceMotion: data.reduceMotion ?? false
    readonly property bool reduceTransparency: data.reduceTransparency ?? false
    readonly property real textScale: data.textScale ?? 1
    readonly property bool alwaysShowScrollbars: data.scrollBars === "always"
    readonly property real glassSolidity: data.glassSolidity ?? 0
    // Notifications (Settings): previews, sounds, and each app's choices,
    // keyed as MacBar's ggKeyOf() names an app.
    readonly property var notifyPrefs: data.notifications ?? ({})
    readonly property string notifyPreviews: notifyPrefs.previews ?? "always"   // always | never
    readonly property bool notifySounds: notifyPrefs.sounds ?? true
    function notifyApp(key) {
        return Object.assign({ allow: true, banners: true, sound: true, badges: true }, FocusPolicy.appChoice(notifyPrefs.apps, key))
    }
    property QtObject focusStatus: Shared.FocusState { policy: prefs.data.focus ?? ({}) }
    readonly property bool nightShift: data.display?.nightShift ?? false
    readonly property int displayWarmth: data.display?.warmth ?? 4500
    readonly property real savedBrightness: data.display?.brightness ?? -1

    FileView {
        id: desktopFile
        path: prefs.file
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { try { prefs.data = JSON.parse(text()) } catch (e) { prefs.data = ({}) } }
        onLoadFailed: prefs.data = ({})
    }
}
