// Golden Gate shell for Quickshell (https://quickshell.org).
// Run with:  qs -p shell/        (or install to ~/.config/quickshell/golden-gate
//                                  and run `qs -c golden-gate`)
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "theme"
import "components"

ShellRoot {
    id: root
    // One AppLaunch per screen; Spotlight picks the one on its own screen.
    property var launchers: []
    Binding { target: Theme; property: "reduceMotion"; value: Prefs.reduceMotion }
    Binding { target: Theme; property: "reduceTransparency"; value: Prefs.reduceTransparency }
    Binding { target: Theme; property: "glassStyle"; value: Prefs.glass }
    // Follow the system appearance set by Control Center, GNOME Settings or gsettings.
    // GTK 3 apps (Mail) have no colour scheme, only a dark theme, so mirror it there.
    function followScheme(line) {
        Theme.dark = line.includes("dark")
        Quickshell.execDetached(["gsettings", "set", "org.gnome.desktop.interface", "gtk-theme", Theme.dark ? "Adwaita-dark" : "Adwaita"])
    }
    Process {
        running: true
        command: ["gsettings", "monitor", "org.gnome.desktop.interface", "color-scheme"]
        stdout: SplitParser { onRead: (line) => followScheme(line) }
    }
    Process {
        running: true
        command: ["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"]
        stdout: SplitParser { onRead: (line) => followScheme(line) }
    }
    // The accent colour (Settings › Appearance › Color), for everything the shell draws.
    function followAccent(line) { const m = /'(\w+)'/.exec(line); if (m) Theme.accentName = m[1] }
    Process {
        running: true
        command: ["gsettings", "monitor", "org.gnome.desktop.interface", "accent-color"]
        stdout: SplitParser { onRead: (line) => followAccent(line) }
    }
    Process {
        running: true
        command: ["gsettings", "get", "org.gnome.desktop.interface", "accent-color"]
        stdout: SplitParser { onRead: (line) => followAccent(line) }
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
    Applications { id: applicationsPanel }
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
    Notifications { id: notificationCenter }
    Switcher {}
    // Loaded separately so a Quickshell built without PAM still runs the shell.
    LazyLoader { active: true; source: "LockScreen.qml" }
    LazyLoader { active: Quickshell.env("GG_LOCK_PREVIEW") === "1"; source: "LockPreview.qml" }

    Variants {
        model: Quickshell.screens
        delegate: Scope {
            id: perScreen
            required property var modelData

            Wallpaper { screen: perScreen.modelData }
            LazyLoader { active: Quickshell.env("GG_WIDGETS") === "1"; source: "DesktopWidgets.qml" }
            ControlCenter { id: cc; screen: perScreen.modelData; notifications: notificationCenter }
            MenuBar { screen: perScreen.modelData; controlCenter: cc; spotlight: spotlightPanel }
            AppLaunch {
                id: launch
                screen: perScreen.modelData
                Component.onCompleted: root.launchers = root.launchers.concat([launch])
                Component.onDestruction: root.launchers = root.launchers.filter((l) => l !== launch)
            }
            Dock { screen: perScreen.modelData; launcher: launch; applications: applicationsPanel }

            IpcHandler {
                target: "controlcenter"
                function toggle(): void { cc.toggle() }
            }
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

