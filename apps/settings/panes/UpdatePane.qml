// Software Update: Golden Gate updates with the rest of Arch Linux, in Terminal.
import Quickshell
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    headerSymbol: "arrow-clockwise"; headerTint: "#8e8e93"; headerTitle: "Software Update"
    headerText: "Golden Gate is updated together with its Arch Linux packages. Updating opens Terminal, where you confirm with your password."
    property string last: ""
    Component.onCompleted: sys.sh("grep -m1 'starting full system upgrade' /var/log/pacman.log 2>/dev/null >/dev/null; tac /var/log/pacman.log 2>/dev/null | grep -m1 'starting full system upgrade' | cut -c2-17", (o) => last = o.trim())
    Group {
        SetRow {
            title: "Update Now"
            subtitle: pane.last ? "Last updated " + pane.last.replace("T", " at ") : "Check for new versions of Golden Gate and your apps."
            Button { text: "Update Now"; prominent: true; onClicked: Quickshell.execDetached(["ghostty", "-e", "sh", "-c", "sudo pacman -Syu; echo; read -p 'Press Return to close.' _"]) }
        }
    }
}
