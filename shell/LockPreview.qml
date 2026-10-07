// Visual preview of the lock surface without locking the session
// (GG_LOCK_PREVIEW=1 qs -c golden-gate; GG_LOCK_PREVIEW=login for the login
// window). Any password shakes. For screenshots and tests:
//   qs ipc call lockpreview wake | fail | check | type <text>
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "components"

PanelWindow {
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "gg-lock-preview"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    LockSurface {
        id: surface
        anchors.fill: parent
        wallpaper: "file://" + Prefs.wallpaper
        message: Prefs.lockMessage
        login: Quickshell.env("GG_LOCK_PREVIEW") === "login"
        battery: 0.82
        onSubmitted: fail()
        Component.onCompleted: reset()
    }
    IpcHandler {
        target: "lockpreview"
        function wake(): void { surface.wake() }
        function fail(): void { surface.fail() }
        function check(): void { surface.wake(); surface.busy = true }
        function type(text: string): void { surface.wake(); surface.typed(text) }
    }
}
