// Users & Groups: you, and the other people with accounts on this computer.
import Quickshell
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    property var users: []        // {login, name, admin, me}
    Component.onCompleted: sys.sh("me=$(id -un); admins=\" $(getent group wheel | cut -d: -f4 | tr , ' ') \"; getent passwd | awk -F: '$3>=1000 && $3<60000 {print $1\":\"$5}' | while IFS=: read -r l n; do a=0; case \"$admins\" in *\" $l \"*) a=1;; esac; printf '%s:%s:%s:%s\\n' \"$l\" \"${n%%,*}\" \"$a\" \"$([ \"$l\" = \"$me\" ] && echo 1 || echo 0)\"; done",
        (o) => users = o.split("\n").filter((l) => l).map((l) => { const f = l.split(":"); return { login: f[0], name: f[1] || f[0], admin: f[2] === "1", me: f[3] === "1" } }))
    Group {
        Repeater {
            model: pane.users
            delegate: SetRow {
                required property var modelData
                title: modelData.name + (modelData.me ? " (you)" : "")
                subtitle: modelData.admin ? "Admin" : "Standard"
                Button { visible: modelData.me; text: "Change Password…"; onClicked: Quickshell.execDetached(["ghostty", "-e", "sh", "-c", "passwd; read -p 'Press Return to close.' _"]) }
            }
        }
    }
}
