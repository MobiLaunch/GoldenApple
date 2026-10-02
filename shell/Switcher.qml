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
import "theme"
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
    WlrLayershell.layer: WlrLayer.Overlay
    mask: Region {}

    // One entry per app, most recently used first, each holding a window to raise.
    function collect() {
        const seen = {}, out = [];
        const tops = ToplevelManager.toplevels.values;
        for (let i = tops.length - 1; i >= 0; i--) {
            const t = tops[i];
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
        apps[index]?.toplevel.activate();
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

    Glass { variant: "clear";
        id: panel
        anchors.centerIn: parent
        width: row.implicitWidth + 28
        height: row.implicitHeight + 28
        radius: 30
        tint: Theme.glassRegular.tint
        scale: sw.open ? 1 : 0.9
        Behavior on scale { Spring { spring: Theme.popover } }

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 8
            Repeater {
                model: sw.apps
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    implicitWidth: 118; implicitHeight: 136
                    radius: 20
                    color: index === sw.index ? Theme.selection : "transparent"
                    border.width: index === sw.index ? 0.5 : 0
                    border.color: Theme.separator
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 6
                        Image {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: 96; Layout.preferredHeight: 96
                            sourceSize: Qt.size(192, 192)
                            source: Quickshell.iconPath(modelData.icon, "application-x-executable")
                        }
                        Text { Layout.alignment: Qt.AlignHCenter; text: modelData.name; color: Theme.label; font { family: Theme.fontUi; pixelSize: 12; weight: Font.Medium } }
                    }
                }
            }
        }
    }
}
