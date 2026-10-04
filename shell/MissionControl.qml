// Mission Control (⌃↑, F3, three fingers up): every window on this desktop,
// spread out side by side, live, with the desktops (Spaces) along the top.
// App Exposé (⌃↓, three fingers down) shows only the front app's windows.
//   - click a window to bring it forward; Escape or a click on empty space
//     goes back to where you were
//   - click a desktop to go to it, + to add one; drag a window onto a desktop
//     to move it there
//   - arrows choose a window, Return brings it forward
// Windows fly from where they are to their place in the spread and back, on
// one curve. Thumbnails are live captures of each window (ScreencopyView,
// Hyprland's toplevel export); a window that can't be captured shows its icon.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Effects
import "ui/theme"
import "components"
import "missioncontrol/layout.js" as Layout

PanelWindow {
    id: mc
    property bool open: false
    property bool appOnly: false            // App Exposé
    property real progress: 0               // 0: windows where they are, 1: spread out
    property int selected: -1
    property var pending: null              // what to do once the windows are back

    readonly property var monitor: Hyprland.monitorFor(screen)
    readonly property int workspaceId: monitor?.activeWorkspace?.id ?? Hyprland.focusedWorkspace?.id ?? 1
    readonly property string frontApp: ToplevelManager.activeToplevel?.appId ?? ""

    function present(apps) {
        Hyprland.refreshToplevels()
        Hyprland.refreshWorkspaces()
        appOnly = !!apps
        selected = -1
        pending = null
        open = true
        spring.to = 1
        spring.restart()
    }
    function dismiss(action) {
        if (!open) return
        pending = action ?? null
        open = false
        spring.to = 0
        spring.restart()
    }
    function toggle(apps) { open && appOnly === !!apps ? dismiss() : present(apps) }

    // The windows of this desktop, from Hyprland, with where they are on screen.
    readonly property var windows: {
        const mon = monitor
        const ox = mon?.x ?? 0, oy = mon?.y ?? 0
        let list = Hyprland.toplevels.values.filter((t) => {
            const o = t.lastIpcObject
            return o && o.at && o.size && (t.workspace?.id ?? o.workspace?.id) === workspaceId && o.mapped !== false && !o.hidden
        })
        if (appOnly && frontApp) {
            const mine = list.filter((t) => (t.lastIpcObject.class || t.wayland?.appId) === frontApp)
            if (mine.length) list = mine
        }
        return list.map((t) => {
            const o = t.lastIpcObject
            return { toplevel: t, address: "0x" + String(t.address ?? o.address).replace(/^0x/, ""),
                     appId: o.class || t.wayland?.appId || "", title: o.title || t.title || "",
                     x: o.at[0] - ox, y: o.at[1] - oy, w: Math.max(40, o.size[0]), h: Math.max(40, o.size[1]) }
        })
    }

    // The spread (missioncontrol/layout.js), below the desktops and above the Dock.
    readonly property rect area: Qt.rect(48, spaces.height + 36, width - 96, height - spaces.height - 36 - 72)
    readonly property var layout: Layout.spread(windows, { x: area.x, y: area.y, width: area.width, height: area.height }, 28, 26)
        .map((r) => Qt.rect(r.x, r.y, r.width, r.height))

    // Desktops on this screen, in order; the one in front is always there.
    readonly property var desktops: {
        const name = monitor?.name
        const ids = Hyprland.workspaces.values
            .filter((w) => w.id > 0 && (!name || !w.monitor || w.monitor.name === name))
            .map((w) => w.id)
        if (!ids.includes(workspaceId)) ids.push(workspaceId)
        return ids.sort((a, b) => a - b)
    }
    function windowsOn(id) {
        return Hyprland.toplevels.values.filter((t) => (t.workspace?.id ?? t.lastIpcObject?.workspace?.id) === id && t.lastIpcObject?.at)
    }

    function focus(i) {
        const w = windows[i]
        if (w) dismiss(() => Hyprland.dispatch("focuswindow address:" + w.address))
    }
    function goTo(id) {
        if (id === workspaceId) dismiss()
        else dismiss(() => Hyprland.dispatch("workspace " + id))
    }
    function moveTo(i, id) {
        const w = windows[i]
        if (!w || id === workspaceId) return
        Hyprland.dispatch("movetoworkspacesilent " + id + ",address:" + w.address)
        Hyprland.refreshToplevels()
    }

    // One curve for the whole move: the system's smooth spring opening, its
    // snappier one going back.
    NumberAnimation {
        id: spring
        target: mc; property: "progress"
        duration: Theme.reduceMotion ? 1 : mc.open ? Theme.smooth.duration : Theme.snappy.duration
        easing.type: Easing.BezierSpline
        easing.bezierCurve: mc.open ? Theme.smooth.curve : Theme.snappy.curve
        onStopped: if (!mc.open && mc.pending) { const a = mc.pending; mc.pending = null; a() }
    }

    visible: open || progress > 0.01
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "gg-missioncontrol"

    // The desktop picture, dimmed, behind everything.
    Item {
        anchors.fill: parent
        opacity: Math.min(1, mc.progress * 1.4)
        Image {
            anchors.fill: parent
            source: Prefs.wallpaper
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            // Softly out of focus, as on the Mac (shader effects need the GPU renderer).
            layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
            layer.effect: MultiEffect { blurEnabled: true; blur: 0.5; blurMax: 48 }
        }
        Rectangle { anchors.fill: parent; color: Theme.dark ? "#73000000" : "#59000000" }
        MouseArea { anchors.fill: parent; onClicked: mc.dismiss() }
    }

    FocusScope {
        anchors.fill: parent
        focus: mc.open
        Keys.onEscapePressed: mc.dismiss()
        Keys.onLeftPressed: mc.selected = Math.max(0, mc.selected < 0 ? 0 : mc.selected - 1)
        Keys.onRightPressed: mc.selected = Math.min(mc.windows.length - 1, mc.selected + 1)
        Keys.onUpPressed: mc.selected = Layout.nearest(mc.layout, mc.selected, -1)
        Keys.onDownPressed: mc.selected = Layout.nearest(mc.layout, mc.selected, 1)
        Keys.onReturnPressed: if (mc.selected >= 0) mc.focus(mc.selected)
        Keys.onEnterPressed: if (mc.selected >= 0) mc.focus(mc.selected)
    }
    // ------------------------------------------------------------ Spaces bar
    Item {
        id: spaces
        width: parent.width
        height: mc.appOnly ? 0 : 150
        visible: !mc.appOnly
        opacity: mc.progress
        y: -24 * (1 - mc.progress)
        readonly property real tileW: 176
        readonly property real tileH: tileW * mc.height / Math.max(1, mc.width)
        property int dropTarget: -1

        Row {
            id: tiles
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 22 }
            spacing: 22
            Repeater {
                model: mc.desktops
                delegate: Column {
                    id: desk
                    required property int modelData
                    required property int index
                    readonly property bool current: modelData === mc.workspaceId
                    readonly property bool target: spaces.dropTarget === modelData
                    spacing: 6
                    Rectangle {
                        width: spaces.tileW; height: spaces.tileH
                        radius: 8
                        color: "#33000000"
                        border { width: desk.current || desk.target ? 3 : 1; color: desk.target ? Theme.accent : desk.current ? "#ffffff" : "#40ffffff" }
                        scale: tileHover.hovered || desk.target ? 1.04 : 1
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        clip: true
                        Image {
                            anchors { fill: parent; margins: parent.border.width }
                            source: Prefs.wallpaper
                            sourceSize: Qt.size(352, 220)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                        // The desktop's windows, in miniature.
                        Repeater {
                            model: mc.windowsOn(desk.modelData)
                            delegate: Rectangle {
                                required property var modelData
                                readonly property var o: modelData.lastIpcObject
                                readonly property real k: spaces.tileW / Math.max(1, mc.width)
                                x: (o.at[0] - (mc.monitor?.x ?? 0)) * k
                                y: (o.at[1] - (mc.monitor?.y ?? 0)) * k
                                width: Math.max(6, o.size[0] * k); height: Math.max(4, o.size[1] * k)
                                radius: 3
                                color: Theme.dark ? "#e62c2c2e" : "#f2f6f6f8"
                                border { width: 0.5; color: "#33000000" }
                                Image {
                                    anchors.centerIn: parent
                                    width: Math.min(18, parent.height * 0.6); height: width
                                    source: Quickshell.iconPath(DesktopEntries.byId(o.class)?.icon ?? o.class, "application-x-executable")
                                    sourceSize: Qt.size(36, 36)
                                }
                            }
                        }
                        HoverHandler { id: tileHover }
                        TapHandler { onTapped: mc.goTo(desk.modelData) }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Desktop " + (desk.index + 1)
                        color: "#ffffff"
                        font { family: Theme.fontUi; pixelSize: 12; weight: desk.current ? Font.DemiBold : Font.Medium }
                    }
                }
            }
        }
        // + adds a desktop (the first empty one) and goes to it.
        Rectangle {
            anchors { right: parent.right; rightMargin: 28; top: tiles.top; topMargin: (spaces.tileH - height) / 2 }
            width: 44; height: 44; radius: 22
            color: plusHover.hovered ? "#59ffffff" : "#33ffffff"
            border { width: 0.5; color: "#59ffffff" }
            Text { anchors.centerIn: parent; text: "+"; color: "#ffffff"; font { family: Theme.fontUi; pixelSize: 24; weight: Font.Light } }
            HoverHandler { id: plusHover }
            TapHandler { onTapped: mc.dismiss(() => Hyprland.dispatch("workspace emptym")) }
            Accessible.role: Accessible.Button
            Accessible.name: "Add Desktop"
        }
        function desktopAt(item, x, y) {
            for (let i = 0; i < tiles.children.length; i++) {
                const c = tiles.children[i]
                if (c.modelData === undefined) continue
                const p = item.mapToItem(c, x, y)
                if (p.x >= 0 && p.y >= 0 && p.x <= c.width && p.y <= spaces.tileH) return c.modelData
            }
            return -1
        }
    }

    // ------------------------------------------------------------ windows
    Repeater {
        model: mc.windows
        delegate: Item {
            id: win
            required property var modelData
            required property int index
            readonly property rect to: mc.layout[index] ?? Qt.rect(modelData.x, modelData.y, modelData.w, modelData.h)
            readonly property real p: mc.progress
            readonly property bool lit: hover.hovered || mc.selected === index
            x: modelData.x + (to.x - modelData.x) * p + drag.dx
            y: modelData.y + (to.y - modelData.y) * p + drag.dy
            width: modelData.w + (to.width - modelData.w) * p
            height: modelData.h + (to.height - modelData.h) * p
            z: drag.active ? 10 : lit ? 2 : 1
            scale: drag.active ? 0.6 : 1
            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            // Where the pointer has dragged it, while dragging.
            QtObject { id: drag; property bool active: false; property real dx: 0; property real dy: 0 }

            Rectangle {      // a soft shadow under the window
                anchors { fill: parent; topMargin: 6; bottomMargin: -6; leftMargin: 2; rightMargin: 2 }
                radius: 14; color: "#40000000"
                opacity: mc.progress
            }
            ScreencopyView {
                id: shot
                anchors.fill: parent
                captureSource: win.modelData.toplevel.wayland ?? null
                live: mc.visible
                visible: hasContent
            }
            // A window that can't be captured: its icon on a plain card.
            Rectangle {
                anchors.fill: parent
                visible: !shot.hasContent
                radius: 14
                color: Theme.dark ? "#2c2c2e" : "#f6f6f8"
                Image {
                    anchors.centerIn: parent
                    width: Math.min(96, parent.width * 0.4, parent.height * 0.5); height: width
                    source: Quickshell.iconPath(DesktopEntries.byId(win.modelData.appId)?.icon ?? win.modelData.appId, "application-x-executable")
                    sourceSize: Qt.size(192, 192)
                }
            }
            Rectangle {      // the highlight: an accent ring around the window under the pointer
                anchors { fill: parent; margins: -4 }
                radius: 18
                color: "transparent"
                border { width: 3; color: Theme.accent }
                opacity: win.lit && mc.open && !drag.active ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
            }
            // The title, under the window, while it's highlighted.
            Rectangle {
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.bottom; topMargin: 10 }
                width: Math.min(title.implicitWidth + 20, Math.max(120, parent.width + 40)); height: 24
                radius: 12
                color: "#b3000000"
                opacity: win.lit && mc.progress > 0.9 && !drag.active ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
                Text {
                    id: title
                    anchors.centerIn: parent
                    width: parent.width - 20
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: win.modelData.title || (DesktopEntries.byId(win.modelData.appId)?.name ?? win.modelData.appId)
                    color: "#ffffff"
                    font { family: Theme.fontUi; pixelSize: 12; weight: Font.Medium }
                }
            }

            HoverHandler { id: hover; enabled: mc.open }
            MouseArea {
                anchors.fill: parent
                enabled: mc.open
                property point start
                property bool moved: false
                onPressed: (m) => { start = Qt.point(m.x, m.y); moved = false }
                onPositionChanged: (m) => {
                    const dx = m.x - start.x, dy = m.y - start.y
                    if (!moved && Math.hypot(dx, dy) < 8) return
                    moved = true
                    drag.active = true
                    drag.dx = dx; drag.dy = dy
                    spaces.dropTarget = spaces.desktopAt(this, m.x, m.y)
                }
                onReleased: (m) => {
                    if (moved) {
                        const target = spaces.desktopAt(this, m.x, m.y)
                        if (target >= 0) mc.moveTo(win.index, target)
                    }
                    drag.active = false; drag.dx = 0; drag.dy = 0
                    spaces.dropTarget = -1
                }
                onClicked: if (!moved) mc.focus(win.index)
            }
        }
    }

    // Nothing on this desktop.
    Text {
        anchors.centerIn: parent
        visible: mc.open && !mc.windows.length
        opacity: mc.progress
        text: mc.appOnly ? "No windows" : "No windows on this desktop"
        color: "#d9ffffff"
        font { family: Theme.fontUi; pixelSize: 15; weight: Font.Medium }
    }
}
