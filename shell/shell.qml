// CitronOS shell for Quickshell (https://quickshell.org).
// Run with:  qs -p shell/        (or install to ~/.config/quickshell/golden-gate
//                                  and run `qs -c golden-gate`)
//
// The menu bar, Dock, Control Center, Spotlight, notifications, desktop
// widgets, window switcher and screenshots are MacShell's (macshell/, see
// third_party/macshell/UPSTREAM.md); the lock screen is MacLock, its own
// process (shell-lock/, `qs -c golden-gate-lock`). CitronOS adds what MacShell
// doesn't have: the wallpaper from Settings, Launchpad, Mission Control,
// Citron, the AirPods and nearby-device cards, the Log Out dialog and the
// tablet Home Screen.
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "ui/theme"
import "components"
import "macshell"

ShellRoot {
    id: root
    // The shell's own output goes to ~/.local/state/golden-gate-shell.log;
    // the journal (and the ISO boot test, over the serial console) hears this.
    Component.onCompleted: Quickshell.execDetached(["logger", "-t", "gg-shell", "desktop ready"])

    // Launchpad (F4, or Applications in the Dock), on the focused screen.
    property var launchpads: []
    IpcHandler {
        target: "launchpad"
        function toggle(): void {
            const name = Hyprland.focusedMonitor?.name
            const l = root.launchpads.find((x) => x.screen?.name === name) ?? root.launchpads[0]
            l?.toggle()
        }
    }
    // One tablet Home Screen per output. Only the currently focused output
    // receives widget-edit commands; other monitors keep their own layout.
    property var tabletHomes: []
    function focusedTabletHome() {
        const name = Hyprland.focusedMonitor?.name
        return tabletHomes.find(h => h.screen?.name === name) ?? tabletHomes[0]
    }
    IpcHandler {
        target: "tablet"
        function edit(): void { if (Prefs.tabletMode && root.focusedTabletHome()) root.focusedTabletHome().editing = true }
        function done(): void { if (root.focusedTabletHome()) root.focusedTabletHome().editing = false }
        function home(): void { root.focusedTabletHome()?.scrollToTop() }
    }
    // Mission Control and App Exposé, on the focused screen (⌃↑ ⌃↓, F3, swipes).
    property var missionControls: []
    function focusedMissionControl() {
        const name = Hyprland.focusedMonitor?.name
        return missionControls.find((m) => m.screen?.name === name) ?? missionControls[0]
    }
    IpcHandler {
        target: "missioncontrol"
        function toggle(): void { root.focusedMissionControl()?.toggle(false) }
        function appExpose(): void { root.focusedMissionControl()?.toggle(true) }
        function close(): void { root.missionControls.forEach((m) => m.dismiss()) }
    }
    // The lock screen is MacLock (shell-lock/), a process of its own so a
    // shell that stops can never take the lock with it. Settings, hypridle
    // and ⌃⌘Q ask for it here, as before.
    IpcHandler {
        target: "lock"
        function lock(): void { Quickshell.execDetached(["gg-lock"]) }
    }
    // ⌥⌘H: hide every window but the front app's.
    IpcHandler {
        target: "menubar"
        function hideOthers(): void {
            const front = Hyprland.activeToplevel?.lastIpcObject?.class ?? ""
            for (const t of Hyprland.toplevels.values) {
                const o = t.lastIpcObject
                if (!o?.address || o.class === front || o.workspace?.name?.startsWith("special:")) continue
                Hyprland.dispatch(`hl.dsp.window.move({ workspace = "special:hidden", follow = false, window = "address:${o.address}" })`)
            }
        }
    }

    Binding { target: Theme; property: "reduceMotion"; value: Prefs.reduceMotion }
    Binding { target: Theme; property: "reduceTransparency"; value: Prefs.reduceTransparency }
    Binding { target: Theme; property: "glassStyle"; value: Prefs.glass }
    Binding { target: Theme; property: "textScale"; value: Prefs.textScale }
    Binding { target: Theme; property: "alwaysShowScrollbars"; value: Prefs.alwaysShowScrollbars }
    Binding { target: Theme; property: "glassSolidity"; value: Prefs.glassSolidity }
    Connections {
        target: Prefs
        function onDataChanged() {
            Quickshell.execDetached(["gg-hyprglass-sync", Theme.dark ? "dark" : "light"])
        }
    }
    // Follow the system appearance set by Control Center, GNOME Settings or gsettings.
    // GTK 3 apps (Mail) have no colour scheme, only a dark theme, so mirror it there.
    function followScheme(line) {
        Theme.dark = line.includes("dark")
        Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.interface", "gtk-theme", Theme.dark ? "Adwaita-dark" : "Adwaita"])
        Quickshell.execDetached(["gg-hyprglass-sync", Theme.dark ? "dark" : "light"])
    }
    Process {
        id: schemeWatch
        running: true
        command: ["gsettings", "monitor", "org.gnome.desktop.interface", "color-scheme"]
        stdout: SplitParser { onRead: (line) => followScheme(line) }
        onExited: settingsRewatch.start()
    }
    Process {
        id: schemeNow
        running: true
        command: ["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"]
        stdout: SplitParser { onRead: (line) => followScheme(line) }
    }
    // The accent colour (Settings › Appearance › Color), for everything the shell draws.
    function followAccent(line) { const m = /'(\w+)'/.exec(line); if (m) Theme.accentName = m[1] }
    Process {
        id: accentWatch
        running: true
        command: ["gsettings", "monitor", "org.gnome.desktop.interface", "accent-color"]
        stdout: SplitParser { onRead: (line) => followAccent(line) }
        onExited: settingsRewatch.start()
    }
    Process {
        id: accentNow
        running: true
        command: ["gsettings", "get", "org.gnome.desktop.interface", "accent-color"]
        stdout: SplitParser { onRead: (line) => followAccent(line) }
    }
    // A monitor that stops (dconf restarted) is started again, and what it
    // missed meanwhile is read afresh.
    Timer {
        id: settingsRewatch
        interval: 3000
        onTriggered: {
            interval = Math.min(interval * 2, 60000)    // and less often if it keeps stopping
            schemeWatch.running = true; accentWatch.running = true
            schemeNow.running = true; accentNow.running = true
        }
    }

    // Appearance "Auto" (chosen in Setup Assistant): light by day, dark from 7 pm.
    FileView {
        id: appearance
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/golden-gate/appearance.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: autoLook.apply(true)
    }
    Timer {
        id: autoLook
        interval: 60000; running: true; repeat: true
        onTriggered: apply(false)
        function apply(initial) {
            let mode = ""
            try { mode = JSON.parse(appearance.text()).mode } catch (e) { return }
            if (!["light", "dark", "auto"].includes(mode) || (mode !== "auto" && !initial)) return
            const h = new Date().getHours(), dark = mode === "dark" || (mode === "auto" && (h < 7 || h >= 19))
            if (dark !== Theme.dark)
                Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", dark ? "prefer-dark" : "default"])
        }
    }

    // Voice is an isolated component so missing Live/audio support can never
    // prevent the desktop from reaching the dock, menus or window switcher.
    LazyLoader { active: true; source: "VoiceAssistant.qml" }
    // First-party AirPods system layer. No separate app; the M10 D-Bus
    // daemon owns transport, and this card displays only trusted events.
    LazyLoader { active: true; source: "CitronPodsPopup.qml" }
    SessionDialog { id: sessionDialog }
    Nearby {}

    Variants {
        model: Quickshell.screens
        delegate: Scope {
            id: perScreen
            required property var modelData

            Wallpaper { screen: perScreen.modelData; onEditWidgets: macShell.widgets.editing = true }
            // A real, touch-first Home Screen behind windows; switching tablet
            // mode doesn't create a separate login session or move desktop files.
            TabletHome {
                id: tabletHome
                screen: perScreen.modelData
                Component.onCompleted: root.tabletHomes = root.tabletHomes.concat([tabletHome])
                Component.onDestruction: root.tabletHomes = root.tabletHomes.filter(h => h !== tabletHome)
            }
            // Persistent per-screen Applications surface. Keeping the object alive
            // removes the lazy-loader race that made the Dock button appear dead.
            Applications {
                id: applicationsPanel
                screen: perScreen.modelData
                dock: macShell.dock
                Component.onCompleted: root.launchpads = root.launchpads.concat([applicationsPanel])
                Component.onDestruction: root.launchpads = root.launchpads.filter((l) => l !== applicationsPanel)
            }
            MissionControl {
                id: missionControl
                screen: perScreen.modelData
                Component.onCompleted: root.missionControls = root.missionControls.concat([missionControl])
                Component.onDestruction: root.missionControls = root.missionControls.filter((m) => m !== missionControl)
            }
        }
    }

    // After Launchpad: its menu bar and Dock share Launchpad's layer (Top),
    // and the surface made last is drawn on top, so they stay over it as on a Mac.
    MacShell { id: macShell; ggWallpaper: Prefs.wallpaper }

    // The yellow light: Hyprland has no minimized state of its own, so a window
    // that asks to be minimized goes to a hidden workspace; the Dock brings it back.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "minimized") return
            const [addr, on] = event.data.split(",")
            const address = addr.startsWith("0x") ? addr : "0x" + addr
            if (on === "1") Hyprland.dispatch(`hl.dsp.window.move({ workspace = "special:minimized", follow = false, window = "address:${address}" })`)
        }
    }
}
