pragma Singleton
// Whether the Trash has anything in it, for the Dock's full or empty can.
// `gio monitor` tells us when ~/.local/share/Trash/files changes, so nothing
// polls; if gio is missing or stops, it looks every 30 seconds instead.
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: trash
    property bool full: false
    readonly property string dir: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/Trash/files"

    function check() { if (!look.running) look.running = true }
    // Empty Trash, as Files does it (gio knows the trash on every mount).
    function empty() {
        Quickshell.execDetached(["sh", "-c", 'gio trash --empty 2>/dev/null || rm -rf "$1/"* "${1%/files}/info/"*', "sh", dir])
        full = false
    }
    Process {
        id: look
        running: true
        command: ["sh", "-c", 'ls -A "$1" 2>/dev/null | head -1', "sh", trash.dir]
        stdout: StdioCollector { onStreamFinished: trash.full = text.trim().length > 0 }
    }
    Process {
        id: watch
        running: true
        // stdbuf: gio holds its lines back when they go to a pipe.
        command: ["sh", "-c", 'mkdir -p "$1" && command -v gio >/dev/null || exit 3; exec stdbuf -oL gio monitor -d "$1"', "sh", trash.dir]
        // A batch of changes (emptying the Trash) is one look, a moment later.
        stdout: SplitParser { onRead: settle.restart() }
        onExited: fallback.start()
    }
    Timer { id: settle; interval: 250; onTriggered: trash.check() }
    // Without the watch: look now and then, and try watching again.
    Timer {
        id: fallback
        interval: 30000
        onTriggered: { trash.check(); watch.running = true }
    }
}
