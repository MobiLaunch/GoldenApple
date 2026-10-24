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
import "../ui" as Shared
import "../ui/FocusPolicy.js" as FocusPolicy

Singleton {
    id: prefs
    readonly property string file: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/golden-gate/desktop.json"
    property var data: ({})

    readonly property string wallpaper: data.wallpaper || Quickshell.env("GG_WALLPAPER") || "/usr/share/backgrounds/golden-gate/club-soda.jpg"
    // Shell glass bends live captures of the windows under it (DesktopBackdrop);
    // off ("glassWindows": false), it bends only the wallpaper.
    readonly property bool glassWindows: data.glassWindows ?? true
    // Settings › Sound: the alert sound (CitronOS's own, ui/assets/sounds),
    // and the chime when power is connected.
    readonly property string alertSound: data.sound?.alert ?? "Crystal"
    readonly property bool chargingSound: data.sound?.charging ?? true
    function soundPath(name) { return decodeURIComponent(Qt.resolvedUrl("../ui/assets/sounds/" + name + ".wav").toString().replace("file://", "")) }
    // Settings › Touch ID & Password: a finger unlocks the lock screen.
    readonly property bool touchIdUnlock: data.touchId?.unlock ?? true
    // Tablet Mode changes presentation only. No tablet-only partition or
    // alternate desktop session; unplugging the keyboard does not lose apps.
    readonly property bool tabletMode: Quickshell.env("GG_TABLET_PREVIEW") === "1" || (data.tablet?.enabled ?? false)
    // Tablet Home Screen widgets are independent of desktop widgets. Their
    // order and sizes survive sign-out, rotation and mode switching.
    readonly property var tabletWidgets: Array.isArray(data.tablet?.widgets) ? data.tablet.widgets : null
    function setTabletWidgets(list) { write("tablet.widgets", list, "Home Screen") }
    readonly property real dockSize: data.dock?.size ?? 54
    readonly property bool dockIndicators: data.dock?.indicators ?? true
    readonly property bool dockShowRecents: data.dock?.showRecents ?? true
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
    function setDockPinned(ids) { write("dock.pinned", ids, "Dock") }
    // Desktop widgets, [{ id, kind, size, col, row }]; null: the default set.
    readonly property var widgets: Array.isArray(data.widgets) ? data.widgets : null
    function setWidgets(list) { write("widgets", list, "widgets") }
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
        return Object.assign({ allow: true, banners: true, sound: true, badges: true }, FocusPolicy.appChoice(notifyPrefs.apps, key))
    }
    // Spotlight (Settings): which kinds of result it shows.
    function spotlightShows(kind) { return (data.spotlight ?? {})[kind] ?? true }
    // Lock Screen (Settings): a message under the clock.
    readonly property string lockMessage: data.lockScreen?.message ?? ""
    property QtObject focusStatus: Shared.FocusState { policy: prefs.data.focus ?? ({}) }
    readonly property bool focusDnd: focusStatus.active
    readonly property string focusSummary: focusStatus.summary
    property bool focusBusy: false
    property string focusError: ""
    Component {
        id: focusWriter
        Process {
            stderr: StdioCollector { id: focusErr }
            onExited: (code) => {
                prefs.focusBusy = false
                if (code !== 0) prefs.focusError = "Focus couldn't be saved: " + (focusErr.text.trim() || "try again")
                else { prefs.focusError = ""; desktopFile.reload() }
                destroy()
            }
        }
    }
    function setFocus(minutes) {
        if (focusBusy) return
        focusBusy = true; focusError = ""
        const session = minutes < 0 ? focusStatus.stop() : focusStatus.start(minutes)
        const p = focusWriter.createObject(prefs, {command:["gg-pref", "focus.session", JSON.stringify(session)]})
        p.running = true
    }
    // Every change the shell makes to a preference: shown at once, saved by
    // gg-pref (which refuses to touch a damaged desktop.json), and if the save
    // fails, put back as it was with a notification saying why: a change that
    // looks made but was never saved is lost at the next login.
    //   Prefs.write("dock.pinned", ids, "Dock")
    property string saveError: ""
    function write(key, value, what) {
        const before = data
        data = setIn(data, key.split("."), value)
        const p = prefWriter.createObject(prefs, { command: ["gg-pref", key, JSON.stringify(value)],
                                                   before: before, key: key, wrote: JSON.stringify(value), what: what || "setting" })
        p.running = true
    }
    function setIn(obj, path, value) {
        const out = Object.assign({}, obj ?? {})
        out[path[0]] = path.length === 1 ? value : setIn(typeof out[path[0]] === "object" && out[path[0]] !== null ? out[path[0]] : {}, path.slice(1), value)
        return out
    }
    Component {
        id: prefWriter
        Process {
            id: w
            property var before
            property string key
            property string wrote
            property string what
            stderr: StdioCollector { id: writeErr }
            onExited: (code) => {
                if (code !== 0) {
                    // Only undo it if nothing changed it again meanwhile.
                    if (JSON.stringify(prefs.valueAt(prefs.data, w.key)) === w.wrote)
                        prefs.data = prefs.setIn(prefs.data, w.key.split("."), prefs.valueAt(w.before, w.key))
                    const why = writeErr.text.trim() || "it couldn't be saved"
                    prefs.saveError = why
                    Quickshell.execDetached(["notify-send", "-a", "CitronOS", "-i", "dialog-warning",
                                             "Your " + w.what + " change wasn't saved", why])
                }
                w.destroy()
            }
        }
    }
    function valueAt(obj, key) {
        let node = obj
        for (const part of key.split(".")) node = (node && typeof node === "object") ? node[part] : undefined
        return node
    }
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
