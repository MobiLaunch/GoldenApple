// Golden Gate shell for Quickshell (https://quickshell.org).
// Run with:  qs -p shell/        (or install to ~/.config/quickshell/golden-gate
//                                  and run `qs -c golden-gate`)
import Quickshell
import Quickshell.Io
import QtQuick
import "theme"

ShellRoot {
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

    Spotlight { id: spotlightPanel }
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
            ControlCenter { id: cc; screen: perScreen.modelData; notifications: notificationCenter }
            MenuBar { screen: perScreen.modelData; controlCenter: cc; spotlight: spotlightPanel }
            Dock { screen: perScreen.modelData }

            IpcHandler {
                target: "controlcenter"
                function toggle(): void { cc.toggle() }
            }
        }
    }
}
