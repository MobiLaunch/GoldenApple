// Lock screen: ext-session-lock surface on every output, PAM authentication.
// hypridle / the system menu lock through IPC:  qs -c golden-gate ipc call lock lock
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import QtQuick
import "theme"
import "components"

Scope {
    id: root
    property string wallpaper: Prefs.wallpaper
    property var surfaces: []

    IpcHandler {
        target: "lock"
        function lock(): void { session.locked = true }
    }

    PamContext {
        id: pam
        config: "login"
        onCompleted: (result) => {
            if (result === PamResult.Success) session.locked = false;
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
                userName: Quickshell.env("USER") ? Quickshell.env("USER").charAt(0).toUpperCase() + Quickshell.env("USER").slice(1) : "Golden User"
                Component.onCompleted: { root.surfaces = root.surfaces.concat([surface]); reset() }
                Component.onDestruction: root.surfaces = root.surfaces.filter((s) => s !== surface)
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
