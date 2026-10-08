// App switcher (⌘Tab). Hold Super and press Tab to step through running apps;
// releasing Super switches. Hyprland binds (compositor/hyprland/hyprland.conf):
//   bind  = SUPER, TAB, global, golden-gate:switcher-next
//   bind  = SUPER SHIFT, TAB, global, golden-gate:switcher-prev
//   bindr = SUPER, SUPER_L, global, golden-gate:switcher-commit
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import "ui/theme"
import "components"

PanelWindow {
    id: sw
    property bool open: false
    property int index: 0
    property var apps: []

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    visible: open
    WlrLayershell.namespace: "gg-switcher"
    // What its glass bends: the desktop under it.
    DesktopBackdrop { surface: sw; namespace: "gg-switcher" }
    WlrLayershell.layer: WlrLayer.Overlay
    mask: Region {}

    // Apps and windows in the order they were last used, newest first: ⌘Tab
    // goes back to the previous app, as on the Mac.
    property var recentApps: []
    property var recentWindows: []
    Connections {
        target: ToplevelManager
        function onActiveToplevelChanged() {
            const t = ToplevelManager.activeToplevel;
            if (!t || !t.appId) return;
            sw.recentApps = [t.appId].concat(sw.recentApps.filter((a) => a !== t.appId)).slice(0, 64);
            sw.recentWindows = [t].concat(sw.recentWindows.filter((w) => w !== t)).slice(0, 128);
        }
    }

    // One entry per app, most recently used first, each holding the app's most
    // recently used window to raise.
    function collect() {
        const seen = {}, out = [];
        const tops = ToplevelManager.toplevels.values;
        const rank = (t) => { const i = recentApps.indexOf(t.appId); return i < 0 ? 1e6 - tops.indexOf(t) : i };
        const used = (t) => { const i = recentWindows.indexOf(t); return i < 0 ? 1e6 : i };
        const ordered = tops.slice().sort((a, b) => rank(a) - rank(b) || used(a) - used(b));
        for (const t of ordered) {
            if (seen[t.appId]) continue;
            seen[t.appId] = true;
            const entry = DesktopEntries.byId(t.appId);
            out.push({ toplevel: t, name: entry ? entry.name : t.appId, icon: entry ? entry.icon : t.appId });
        }
        const active = out.findIndex((a) => a.toplevel.activated);
        if (active > 0) out.unshift(out.splice(active, 1)[0]);
        return out;
    }
    function step(d) {
        if (!open) { apps = collect(); if (apps.length < 1) return; index = 0; open = true }
        index = (index + d + apps.length) % apps.length;
    }
    function commit() {
        if (!open) return;
        open = false;
        const t = apps[index]?.toplevel;
        if (!t) return;
        // A hidden (⌘H) or minimised window comes back to this Space first, as
        // on the Mac; activating it in place would only peek its special workspace.
        const parked = Hyprland.toplevels.values.find((h) => h.wayland === t
            && (h.workspace?.name === "special:hidden" || h.workspace?.name === "special:minimized"));
        const address = parked ? (parked.address ? "0x" + parked.address.replace(/^0x/, "") : parked.lastIpcObject?.address) : "";
        if (address) Hyprland.dispatch("movetoworkspace " + (Hyprland.focusedWorkspace?.id ?? 1) + ",address:" + address);
        t.activate();
    }

    GlobalShortcut { appid: "golden-gate"; name: "switcher-next"; description: "App switcher: next"; onPressed: sw.step(1) }
    GlobalShortcut { appid: "golden-gate"; name: "switcher-prev"; description: "App switcher: previous"; onPressed: sw.step(-1) }
    GlobalShortcut { appid: "golden-gate"; name: "switcher-commit"; description: "App switcher: switch"; onPressed: sw.commit() }
    IpcHandler {
        target: "switcher"
        function next(): void { sw.step(1) }
        function prev(): void { sw.step(-1) }
        function commit(): void { sw.commit() }
    }

    Glass {
        id: panel
        anchors.centerIn: parent
        width: row.implicitWidth + 28
        height: row.implicitHeight + 28
        role: "regular"
        radius: 30
        scale: sw.open ? 1 : 0.9
        Behavior on scale { Spring { spring: Theme.popover } }

        // One selection that springs from app to app as Tab moves it.
        Rectangle {
            objectName: "switcherSelection"
            visible: sw.apps.length > 0
            x: row.x + Math.max(0, sw.index) * (118 + row.spacing)
            y: row.y
            width: 118; height: 136
            radius: 20
            color: Theme.selection
            border { width: 0.5; color: Theme.separator }
            // Placed at once while closed, so it opens where it should be.
            Behavior on x { enabled: !Theme.reduceMotion && sw.open; Spring { spring: Theme.snappy } }
        }
        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 8
            Repeater {
                model: sw.apps
                delegate: Item {
                    required property var modelData
                    required property int index
                    implicitWidth: 118; implicitHeight: 136
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        Image {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 96; Layout.preferredHeight: 96
                            sourceSize: Qt.size(192, 192)
                            source: Quickshell.iconPath(modelData.icon, "application-x-executable")
                        }
                        Text { Layout.alignment: Qt.AlignHCenter; text: modelData.name; color: Theme.label; font { family: Theme.fontUi; pixelSize: Theme.fs(12); weight: Font.Medium } }
                    }
                }
            }
        }
    }
}
