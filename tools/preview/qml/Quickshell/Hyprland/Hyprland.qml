pragma Singleton
import QtQuick
QtObject {
    readonly property QtObject focusedMonitor: QtObject { readonly property string name: "eDP-1"; readonly property int id: 0; readonly property real scale: 1 }
    readonly property QtObject focusedWorkspace: QtObject { readonly property int id: 1; readonly property string name: "1" }
    readonly property QtObject toplevels: QtObject { readonly property var values: [] }
    readonly property QtObject monitors: QtObject { readonly property var values: [focusedMonitor] }
    readonly property QtObject workspaces: QtObject { readonly property var values: [focusedWorkspace] }
    readonly property var activeToplevel: __preview.env["GG_PREVIEW_ACTIVE"] ? ({ address: "5a5a5a5a5a5a", title: "" }) : null
    signal rawEvent(var event)
    function dispatch(request) { __preview.log("hyprland " + request) }
    function monitorFor(screen) { return focusedMonitor }
    function refreshToplevels() {}
    function refreshMonitors() {}
    function refreshWorkspaces() {}
}
