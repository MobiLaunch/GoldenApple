// Golden Gate shell for Quickshell (https://quickshell.org).
// Run with:  qs -p shell/        (or install to ~/.config/quickshell/golden-gate
//                                  and run `qs -c golden-gate`)
import Quickshell
import Quickshell.Io
import QtQuick
import "theme"

ShellRoot {
    // Follow the system appearance set by Control Center / gsettings.
    Process {
        running: true
        command: ["gsettings", "monitor", "org.gnome.desktop.interface", "color-scheme"]
        stdout: SplitParser { onRead: (line) => Theme.dark = line.includes("dark") }
    }
    Process {
        running: true
        command: ["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"]
        stdout: SplitParser { onRead: (line) => Theme.dark = line.includes("dark") }
    }

    Spotlight { id: spotlightPanel }

    Variants {
        model: Quickshell.screens
        delegate: Scope {
            id: perScreen
            required property var modelData

            ControlCenter { id: cc; screen: perScreen.modelData }
            MenuBar { screen: perScreen.modelData; controlCenter: cc; spotlight: spotlightPanel }
            Dock { screen: perScreen.modelData }

            IpcHandler {
                target: "controlcenter"
                function toggle(): void { cc.toggle() }
            }
        }
    }
}
