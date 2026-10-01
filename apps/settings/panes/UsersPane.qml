// Users & Groups: you, and the other people with accounts on this computer.
import Quickshell
import Quickshell.Io
import QtQuick
import "../../lib"
import "../../lib/theme"
import ".."

Pane {
    id: pane
    property var users: []        // {login, name, admin, me}
    readonly property string helper: Qt.resolvedUrl("../account-helper.py").toString().replace("file://", "")
    property bool changingPassword: false
    property bool passwordBusy: false
    property string newPassword: ""
    property string confirmPassword: ""
    property string passwordMessage: ""
    property bool passwordOkay: false

    function savePassword() {
        passwordMessage = ""
        passwordOkay = false
        if (newPassword.length < 6) {
            passwordMessage = "Use at least 6 characters."
            return
        }
        if (newPassword !== confirmPassword) {
            passwordMessage = "Passwords do not match."
            return
        }
        passwordBusy = true
        passwordProcess.command = ["pkexec", "python3", helper, "password"]
        passwordProcess.running = true
    }

    Process {
        id: passwordProcess
        stdinEnabled: true
        stdout: StdioCollector { id: passwordOut }
        onStarted: {
            write(JSON.stringify({ password: pane.newPassword }))
            stdinEnabled = false
        }
        onExited: (code) => {
            stdinEnabled = true
            pane.passwordBusy = false
            let result = null
            try { result = JSON.parse(passwordOut.text.trim()) } catch (e) {}
            if (code === 0 && result?.ok) {
                pane.passwordOkay = true
                pane.passwordMessage = result.message ?? "Password changed."
                pane.newPassword = ""
                pane.confirmPassword = ""
                pane.changingPassword = false
            } else {
                pane.passwordOkay = false
                pane.passwordMessage = result?.message
                    ?? (code === 126 || code === 127
                        ? "Administrator authorization was cancelled."
                        : "The password could not be changed.")
            }
        }
    }
    Component.onCompleted: sys.sh("me=$(id -un); admins=\" $(getent group wheel | cut -d: -f4 | tr , ' ') \"; getent passwd | awk -F: '$3>=1000 && $3<60000 {print $1\":\"$5}' | while IFS=: read -r l n; do a=0; case \"$admins\" in *\" $l \"*) a=1;; esac; printf '%s:%s:%s:%s\\n' \"$l\" \"${n%%,*}\" \"$a\" \"$([ \"$l\" = \"$me\" ] && echo 1 || echo 0)\"; done",
        (o) => users = o.split("\n").filter((l) => l).map((l) => { const f = l.split(":"); return { login: f[0], name: f[1] || f[0], admin: f[2] === "1", me: f[3] === "1" } }))
    Group {
        Repeater {
            model: pane.users
            delegate: SetRow {
                required property var modelData
                title: modelData.name + (modelData.me ? " (you)" : "")
                subtitle: modelData.admin ? "Admin" : "Standard"
                Button {
                    visible: modelData.me
                    text: pane.changingPassword ? "Cancel" : "Change Password…"
                    onClicked: {
                        pane.passwordMessage = ""
                        pane.passwordOkay = false
                        pane.changingPassword = !pane.changingPassword
                        if (!pane.changingPassword) {
                            pane.newPassword = ""
                            pane.confirmPassword = ""
                        }
                    }
                }
            }
        }
    }

    Group {
        visible: pane.changingPassword
        title: "Change Password"
        SetRow {
            title: "New password"
            TextField {
                width: 220
                password: true
                placeholder: "At least 6 characters"
                text: pane.newPassword
                onTextChanged: pane.newPassword = text
            }
        }
        SetRow {
            title: "Verify password"
            TextField {
                width: 220
                password: true
                placeholder: "Type it again"
                text: pane.confirmPassword
                onTextChanged: pane.confirmPassword = text
                onAccepted: pane.savePassword()
            }
        }
        SetRow {
            title: pane.passwordBusy ? "Waiting for administrator authorization…"
                : pane.passwordMessage
                    ? pane.passwordMessage
                    : "Your password protects this local account."
            Button {
                text: pane.passwordBusy ? "Changing…" : "Change Password"
                prominent: true
                enabled: !pane.passwordBusy
                    && pane.newPassword.length >= 6
                    && pane.newPassword === pane.confirmPassword
                onClicked: pane.savePassword()
            }
        }
    }

    Group {
        visible: !pane.changingPassword && !!pane.passwordMessage
        SetRow {
            title: pane.passwordMessage
            subtitle: pane.passwordOkay ? "Your new password will be used the next time authentication is required." : ""
        }
    }
}
