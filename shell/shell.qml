// CitronOS shell for Quickshell (https://quickshell.org).
// Run with:  qs -p shell/        (or install to ~/.config/quickshell/golden-gate
//                                  and run `qs -c golden-gate`)
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "ui/theme"
import "components"

ShellRoot {
    id: root
    // The shell's own output goes to ~/.local/state/golden-gate-shell.log;
    // the journal (and the ISO boot test, over the serial console) hears this.
    Component.onCompleted: Quickshell.execDetached(["logger", "-t", "gg-shell", "desktop ready"])
    // One AppLaunch per screen; Spotlight picks the one on its own screen.
    property var launchers: []
    // Launchpad (F4, or the Dock's Applications), on the focused screen.
    property var launchpads: []
    IpcHandler {
        target: "launchpad"
        function toggle(): void {
            const name = Hyprland.focusedMonitor?.name
            const l = root.launchpads.find((x) => x.screen?.name === name) ?? root.launchpads[0]
            l?.toggle()
        }
    }
    // One Control Center per screen; ⌥⌘C toggles the one on the focused screen.
    property var controlCenters: []
    function focusedControlCenter() {
        const name = Hyprland.focusedMonitor?.name
        return controlCenters.find((c) => c.screen?.name === name) ?? controlCenters[0]
    }
    IpcHandler {
        target: "controlcenter"
        function toggle(): void { root.focusedControlCenter()?.toggle() }
        // wifi | bluetooth | sound: open Control Center at that module's detail view.
        function detail(kind: string): void {
            const cc = root.focusedControlCenter()
            if (!cc) return
            if (!cc.open) cc.toggle()
            cc.showDetail(kind)
        }
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
    // The menu bar's menus on the focused screen: system | app | window.
    property var menuBars: []
    IpcHandler {
        target: "menubar"
        function open(menu: string): void {
            const name = Hyprland.focusedMonitor?.name
            const m = root.menuBars.find((x) => x.screen?.name === name) ?? root.menuBars[0]
            m?.openMenu(menu)
        }
        // ⌥⌘H: hide every window but the front app's.
        function hideOthers(): void {
            const m = root.menuBars[0]
            m?.hideOthers(m.active ? String(m.active.appId) : "")
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

    Spotlight { id: spotlightPanel; launchers: root.launchers }
    // Voice is an isolated component so missing Live/audio support can never
    // prevent the desktop from reaching the dock, menus or window switcher.
    LazyLoader { active: true; source: "VoiceAssistant.qml" }
    // For tests: launch an app as if from the middle of the Dock, and stand in for
    // Hyprland's "window opened" where there is no Hyprland (qs ipc call launch …).
    IpcHandler {
        target: "launch"
        function app(id: string): void {
            const l = root.launchers[0], e = DesktopEntries.byId(id)
            if (l && e) l.launch(e, Qt.rect(l.width / 2 - 27, l.height - 68, 54, 54))
        }
        function opened(x: int, y: int, w: int, h: int): void { root.launchers[0]?.landOn(Qt.rect(x, y, w, h)) }
    }
    Screenshot { id: screenshots }
    Notifications { id: notificationCenter; controlCenterOpen: root.controlCenters.some((c) => c.open) }
    SessionDialog { id: sessionDialog }
    Osd {}
    DesktopWidgets { id: desktopWidgets }
    Nearby {}
    Switcher {}
    // Loaded separately so a Quickshell built without PAM still runs the shell.
    LazyLoader { active: true; source: "LockScreen.qml" }
    LazyLoader { active: Quickshell.env("GG_LOCK_PREVIEW") === "1"; source: "LockPreview.qml" }

    Variants {
        model: Quickshell.screens
        delegate: Scope {
            id: perScreen
            required property var modelData

            Wallpaper { screen: perScreen.modelData; onEditWidgets: desktopWidgets.editing = true }
            // Persistent per-screen Applications surface. Keeping the object alive
            // removes the lazy-loader race that made the Dock button appear dead.
            Applications {
                id: applicationsPanel
                screen: perScreen.modelData
                Component.onCompleted: root.launchpads = root.launchpads.concat([applicationsPanel])
                Component.onDestruction: root.launchpads = root.launchpads.filter((l) => l !== applicationsPanel)
            }
            ControlCenter {
                id: cc
                screen: perScreen.modelData
                notifications: notificationCenter
                Component.onCompleted: root.controlCenters = root.controlCenters.concat([cc])
                Component.onDestruction: root.controlCenters = root.controlCenters.filter((c) => c !== cc)
            }
            MenuBar {
                id: menuBar
                screen: perScreen.modelData; controlCenter: cc; spotlight: spotlightPanel; session: sessionDialog; notifications: notificationCenter
                screenshots: screenshots
                Component.onCompleted: root.menuBars = root.menuBars.concat([menuBar])
                Component.onDestruction: root.menuBars = root.menuBars.filter((m) => m !== menuBar)
            }
            MissionControl {
                id: missionControl
                screen: perScreen.modelData
                Component.onCompleted: root.missionControls = root.missionControls.concat([missionControl])
                Component.onDestruction: root.missionControls = root.missionControls.filter((m) => m !== missionControl)
            }
            AppLaunch {
                id: launch
                screen: perScreen.modelData
                dock: screenDock
                Component.onCompleted: root.launchers = root.launchers.concat([launch])
                Component.onDestruction: root.launchers = root.launchers.filter((l) => l !== launch)
            }
            Dock { id: screenDock; screen: perScreen.modelData; launcher: launch; applications: applicationsPanel; notifications: notificationCenter }
        }
    }

    // The yellow light: Hyprland has no minimized state of its own, so a window
    // that asks to be minimized goes to a hidden workspace; the Dock brings it back.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "minimized") return
            const [addr, on] = event.data.split(",")
            if (on === "1") Hyprland.dispatch("movetoworkspacesilent special:minimized,address:" + (addr.startsWith("0x") ? addr : "0x" + addr))
        }
    }
}

