pragma Singleton
import QtQuick
// --env GG_PREVIEW_WINDOWS=1 puts a few windows on three desktops (for Mission
// Control and the Spaces bar); GG_PREVIEW_ACTIVE names the app in front.
QtObject {
    id: hypr
    // "empty": the same three desktops with nothing on them (a reference for tests).
    readonly property bool __windows: __preview.env["GG_PREVIEW_WINDOWS"] === "1" || __preview.env["GG_PREVIEW_WINDOWS"] === "empty"
    readonly property bool __empty: __preview.env["GG_PREVIEW_WINDOWS"] === "empty"
    readonly property QtObject focusedWorkspace: QtObject { readonly property int id: 1; readonly property string name: "1" }
    readonly property QtObject focusedMonitor: QtObject {
        readonly property string name: "eDP-1"; readonly property int id: 0; readonly property real scale: 1
        readonly property int x: 0; readonly property int y: 0
        readonly property var activeWorkspace: hypr.focusedWorkspace
    }
    function __ws(id) { return { id: id, name: String(id), monitor: focusedMonitor } }
    function __win(n, app, title, ws, x, y, w, h) {
        const o = { address: "0x5a5a" + n, class: app, title: title, at: [x, y], size: [w, h], workspace: { id: ws, name: String(ws) }, mapped: true, hidden: false, floating: true }
        return { address: o.address, title: title, workspace: __ws(ws), lastIpcObject: o, wayland: { appId: app, title: title } }
    }
    readonly property var __sample: __windows && !__empty ? [
        __win(1, "org.goldengate.Files", "Home", 1, 90, 80, 880, 560),
        __win(2, "org.goldengate.Notes", "CitronOS brief", 1, 640, 170, 700, 520),
        __win(3, "org.goldengate.Music", "Music", 1, 220, 400, 780, 430),
        __win(4, "org.goldengate.Weather", "San Francisco", 1, 1010, 60, 400, 330),
        __win(5, "org.goldengate.Web", "Start Page", 2, 120, 60, 1200, 760),
        __win(6, "org.goldengate.Terminal", "jordan@golden-gate: ~", 2, 700, 420, 640, 380),
        __win(7, "org.goldengate.Messages", "Messages", 3, 300, 120, 840, 600)
    ] : []
    readonly property QtObject toplevels: QtObject { readonly property var values: hypr.__sample }
    readonly property QtObject monitors: QtObject { readonly property var values: [hypr.focusedMonitor] }
    readonly property QtObject workspaces: QtObject { readonly property var values: hypr.__windows ? [1, 2, 3].map((i) => hypr.__ws(i)) : [hypr.focusedWorkspace] }
    readonly property var activeToplevel: __preview.env["GG_PREVIEW_ACTIVE"] ? ({ address: "5a5a5a5a5a5a", title: "" }) : null
    signal rawEvent(var event)
    function dispatch(request) { __preview.log("hyprland " + request) }
    function monitorFor(screen) { return focusedMonitor }
    function refreshToplevels() {}
    function refreshMonitors() {}
    function refreshWorkspaces() {}
}
