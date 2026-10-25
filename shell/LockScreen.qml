// Lock screen: ext-session-lock surface on every output, PAM authentication.
// It runs in a process of its own (lock-shell.qml, citronos-lock.service);
// hypridle, ⌃⌘Q and the menus lock with gg-lock.
// The right password plays the surface's unlock animation on every screen, and
// the session is released when it ends, onto the desktop's same wallpaper.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Services.UPower
import Quickshell.Services.Mpris
import QtQuick
import "ui/theme"
import "components"
import "ui/paths.js" as Paths

Scope {
    id: root
    property string wallpaper: Prefs.wallpaper
    property var surfaces: []
    readonly property string user: Quickshell.env("USER") ?? ""
    readonly property string home: Quickshell.env("HOME") ?? ""
    property string realName: ""
    readonly property var mediaPlayer: Mpris.players.values.length ? Mpris.players.values[0] : null

    IpcHandler {
        target: "lock"
        function lock(): void { session.locked = true }
        // Whether the compositor has confirmed the lock (the session harness asks).
        function isLocked(): bool { return session.secure }
    }
    // The session is locked while this file is there (gg-lock makes it first):
    // a lock screen that starts then, after a crash, locks at once, and
    // unlocking removes it.
    readonly property string marker: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/citronos-locked"
    Process {
        id: markerCheck
        running: true
        command: ["test", "-e", root.marker]
        onExited: (code) => { if (code === 0) session.locked = true }
    }
    // Only signing in ends the locked session. The compositor can end or
    // refuse a lock too: a lock screen started straight after a crash may ask
    // while the compositor still counts the dead one's lock (the fork writing
    // its core dump keeps its connection open), and is refused. Quickshell
    // reports that as an unlock; while the marker is there, ask again. Signing
    // in removes the marker first, then unlocks, so nothing asking again can
    // lock the session straight after.
    property bool signedIn: false
    Timer { id: relock; interval: 300; onTriggered: if (!session.locked) markerCheck.running = true }
    Process {
        id: clearMarker
        command: ["rm", "-f", root.marker]
        onExited: { root.signedIn = true; session.locked = false }
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
            if (result === PamResult.Success) { touch.abort(); root.surfaces.forEach((s) => s.unlock()) }
            else root.surfaces.forEach((s) => s.fail());
        }
    }

    // Touch ID: while locked, a finger on the reader unlocks too, beside the
    // password. It's a PAM service of its own (/etc/pam.d/gg-touchid, only
    // pam_fprintd), listening again after each try. Only with a finger
    // enrolled (Settings › Touch ID & Password) and "Unlock with Touch ID" on.
    property bool touchId: false
    Process {
        id: fingers
        command: ["fprintd-list", root.user]
        stdout: StdioCollector { onStreamFinished: root.touchId = Prefs.touchIdUnlock && /^\s*-\s*#\d+:/m.test(text) }
    }
    Connections {
        target: session
        function onLockedChanged() {
            if (session.locked) {
                Quickshell.execDetached(["touch", root.marker])
                root.touchId = false; if (Prefs.touchIdUnlock) fingers.running = true
            } else {
                root.touchId = false; touch.abort()
                if (root.signedIn) root.signedIn = false
                else relock.restart()
            }
        }
    }
    onTouchIdChanged: if (touchId && session.locked && !touch.active) touch.start()
    PamContext {
        id: touch
        config: "gg-touchid"
        onCompleted: (result) => {
            if (!session.locked) return
            if (result === PamResult.Success) { if (pam.active) pam.abort(); root.surfaces.forEach((s) => s.unlock()); return }
            listenAgain.restart()
        }
        // Each finger that doesn't match (pam_fprintd says so as an error
        // message): the field shakes then, not only once three have missed.
        // Its "Verification timed out" is an error too, but nobody touched
        // the reader then: no shake every half minute on an idle lock screen.
        onPamMessage: if (touch.messageIsError && session.locked && !/timed? ?out/i.test(touch.message))
            root.surfaces.forEach((s) => s.fingerFailed())
    }
    // The reader is asked again after a try (or a timeout), while locked.
    Timer { id: listenAgain; interval: 700; onTriggered: if (session.locked && root.touchId && !touch.active) touch.start() }

    WlSessionLock {
        id: session
        locked: false
        WlSessionLockSurface {
            color: "black"
            LockSurface {
                id: surface
                anchors.fill: parent
                wallpaper: Paths.fileUrl(root.wallpaper)
                tabletMode: Prefs.tabletMode
                player: root.mediaPlayer
                message: Prefs.lockMessage
                touchId: root.touchId
                userName: root.realName || (root.user ? root.user.charAt(0).toUpperCase() + root.user.slice(1) : "Golden User")
                // ~/.face, else the picture AccountsService keeps for the account.
                avatars: ["file://" + root.home + "/.face", "file:///var/lib/AccountsService/icons/" + root.user]
                battery: Battery.present ? Battery.level : -1
                charging: Battery.charging
                Component.onCompleted: { root.surfaces = root.surfaces.concat([surface]); reset() }
                Component.onDestruction: root.surfaces = root.surfaces.filter((s) => s !== surface)
                onUnlocked: clearMarker.running = true
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
