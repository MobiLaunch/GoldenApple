// Lock screen: ext-session-lock surface on every output, PAM authentication.
// hypridle / the system menu lock through IPC:  qs -c golden-gate ipc call lock lock
// The right password plays the surface's unlock animation on every screen, and
// the session is released when it ends, onto the desktop's same wallpaper.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Services.UPower
import QtQuick
import "ui/theme"
import "components"

Scope {
    id: root
    property string wallpaper: Prefs.wallpaper
    property var surfaces: []
    readonly property string user: Quickshell.env("USER") ?? ""
    readonly property string home: Quickshell.env("HOME") ?? ""
    property string realName: ""

    IpcHandler {
        target: "lock"
        function lock(): void { session.locked = true }
    }

    // The account's full name, for under the picture.
    Process {
        running: root.user !== ""
        command: ["getent", "passwd", root.user]
        stdout: StdioCollector { onStreamFinished: root.realName = (text.split(":")[4] ?? "").split(",")[0].trim() }
    }

    PamContext {
        id: pam
        config: "login"
        onCompleted: (result) => {
            if (result === PamResult.Success) root.surfaces.forEach((s) => s.unlock());
            else root.surfaces.forEach((s) => s.fail());
        }
    }

    WlSessionLock {
        id: session
        locked: false
        WlSessionLockSurface {
            color: "black"
            LockSurface {
                id: surface
                anchors.fill: parent
                wallpaper: "file://" + root.wallpaper
                message: Prefs.lockMessage
                userName: root.realName || (root.user ? root.user.charAt(0).toUpperCase() + root.user.slice(1) : "Golden User")
                // ~/.face, else the picture AccountsService keeps for the account.
                avatars: ["file://" + root.home + "/.face", "file:///var/lib/AccountsService/icons/" + root.user]
                battery: UPower.displayDevice.isLaptopBattery ? UPower.displayDevice.percentage : -1
                charging: UPower.displayDevice.state === UPowerDeviceState.Charging || UPower.displayDevice.state === UPowerDeviceState.FullyCharged
                Component.onCompleted: { root.surfaces = root.surfaces.concat([surface]); reset() }
                Component.onDestruction: root.surfaces = root.surfaces.filter((s) => s !== surface)
                onUnlocked: session.locked = false
                // Store the password before starting PAM: it may ask for it at once. An empty
                // password is a valid answer (the live session's user has none).
                onSubmitted: (password) => {
                    if (pam.active) return;
                    pendingPassword = password;
                    awaiting = true;
                    pam.start();
                }
                property string pendingPassword
                property bool awaiting: false
                Connections {
                    target: pam
                    function onResponseRequiredChanged() {
                        if (!pam.responseRequired || !surface.awaiting) return;
                        surface.awaiting = false;
                        pam.respond(surface.pendingPassword);
                        surface.pendingPassword = "";
                    }
                    function onCompleted() { surface.awaiting = false }
                }
            }
        }
    }
}
