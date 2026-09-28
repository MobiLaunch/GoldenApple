// Privacy & Security: Location Services and Analytics (the same choices as in
// Setup Assistant, in privacy.json), and the diagnostics reports.
import Quickshell
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    headerSymbol: "shield"; headerTint: "#0a84ff"; headerTitle: "Privacy & Security"
    headerText: "Nothing leaves this computer unless you choose to share it."
    readonly property var p: sys.privacy
    Group {
        title: "Privacy"
        SetRow {
            title: "Location Services"; symbol: "location"; symbolTint: "#0a84ff"
            subtitle: "Lets apps like Maps and Weather use your approximate location."
            Switch { checked: pane.p.location ?? true; onToggled: (on) => { pane.sys.setPrivacy("location", on); pane.sys.run(["gsettings", "set", "org.gnome.system.location", "enabled", String(on)]) } }
        }
    }
    Group {
        title: "Analytics & Improvements"
        SetRow {
            title: "Share crash and diagnostics logs"
            subtitle: "When something quits unexpectedly you're offered a report to send; nothing is sent until you do."
            Switch {
                checked: pane.p.shareDiagnostics ?? false
                onToggled: (on) => {
                    pane.sys.setPrivacy("shareDiagnostics", on)
                    if (on) Quickshell.execDetached(["sh", "-c", 'pgrep -f crash-watch.sh >/dev/null || setsid -f bash "$1" >/dev/null 2>&1', "sh", Qt.resolvedUrl("../../setup/crash-watch.sh").toString().replace("file://", "")])
                }
            }
        }
        SetRow {
            title: "Share crash data with app developers"
            Switch { checked: pane.p.shareWithDevelopers ?? false; onToggled: (on) => pane.sys.setPrivacy("shareWithDevelopers", on) }
        }
        SetRow {
            title: "Diagnostics reports"
            subtitle: "Reports are kept in Documents › Diagnostics."
            Button { text: "Show Reports"; onClicked: Quickshell.execDetached(["sh", "-c", 'd="$(xdg-user-dir DOCUMENTS 2>/dev/null || echo "$HOME/Documents")/Diagnostics"; mkdir -p "$d"; xdg-open "$d"']) }
            Button { text: "Create Report"; onClicked: Quickshell.execDetached(["bash", Qt.resolvedUrl("../../setup/diagnostics.sh").toString().replace("file://", "")]) }
        }
    }
}
