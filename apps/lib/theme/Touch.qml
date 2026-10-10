pragma Singleton
// Shared tablet/touch mode state. Every Quickshell app observes the same
// Settings preference, so hit targets grow without spawning mobile copies.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: touch
    property bool enabled: Quickshell.env("GG_TABLET_PREVIEW") === "1"
    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") +
              "/golden-gate/desktop.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                touch.enabled = Quickshell.env("GG_TABLET_PREVIEW") === "1" ||
                    (JSON.parse(text()).tablet?.enabled === true)
            } catch (e) {}
        }
    }
}
