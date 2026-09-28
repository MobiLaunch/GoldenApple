// Visual preview of the lock surface without locking the session
// (GG_LOCK_PREVIEW=1 qs -c golden-gate). Any password shakes.
import Quickshell
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
        anchors.fill: parent
        wallpaper: "file://" + Prefs.wallpaper
        hint: "Preview · any password shakes"
        onSubmitted: fail()
    }
}
