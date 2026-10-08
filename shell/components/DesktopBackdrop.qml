// What's behind a shell surface's glass, drawn again inside the surface so
// its glass can bend it (ui/Glass.qml, ui/shaders/glasslens.frag): the
// wallpaper, where it is on the screen, and live captures of the windows on
// this screen's desktop that reach under the surface, the most recently used
// on top. It's never shown itself: one texture of it, the size of the
// surface, is what every piece of glass in the surface samples.
//
//   DesktopBackdrop { surface: dock; namespace: "gg-dock" }
//
// The surface's place on the screen comes from Hyprland's list of layer
// surfaces (a layer surface doesn't know it), or is given (`at`, for a popup
// over another surface). The compositor still blurs behind the surface: that
// is what shows where there's no glass, and wherever the lens is off.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import "../ui/theme"

Item {
    id: bd
    required property var surface
    property string namespace: ""
    property bool includeWindows: true       // false for surfaces under the windows (desktop widgets)
    property point at: Qt.point(0, 0)        // the surface's top-left on its screen
    property var fixedAt: null               // given instead (a popup: its parent's place and its anchor)
    property bool placed: false
    readonly property var screen: surface.screen
    readonly property bool shown: surface.visible && !Theme.reduceTransparency && GraphicsInfo.api !== GraphicsInfo.Software

    parent: surface.contentItem
    // Never drawn in the surface itself, only into the texture (which renders
    // it all the same). Shown and hidden with the texture instead, a frame of
    // it could reach the screen: a box of wallpaper (or, before the image was
    // in, of plain blue) round a menu, filling the popup's spare room.
    visible: false
    x: -at.x; y: -at.y
    width: screen?.width ?? 0
    height: screen?.height ?? 0
    z: -1000

    Image {
        id: wallpaper
        anchors.fill: parent
        source: "file://" + Prefs.wallpaper
        sourceSize: Qt.size(bd.width, bd.height)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
    }

    // The windows under the surface, bottom to top, live while it shows.
    readonly property var windows: {
        if (!includeWindows || !Prefs.glassWindows || !shown) return []
        const mon = Hyprland.monitorFor(bd.screen)
        const ws = mon?.activeWorkspace?.id
        const ox = mon?.x ?? 0, oy = mon?.y ?? 0
        const r = Qt.rect(at.x, at.y, surface.width, surface.height)
        return Hyprland.toplevels.values
            .map((t) => ({ t: t, o: t.lastIpcObject }))
            .filter(({ o }) => o?.at && o.size && !o.hidden && o.workspace?.id === ws && (o.monitor === undefined || o.monitor === mon?.id))
            .map(({ t, o }) => ({ id: bd.addressOf(t.address ?? o.address), x: o.at[0] - ox, y: o.at[1] - oy, w: o.size[0], h: o.size[1], order: o.focusHistoryID ?? 0, live: !!t.wayland }))
            .filter((w) => w.id && w.live && !bd.closing[w.id] && w.x < r.x + r.width && w.x + w.w > r.x && w.y < r.y + r.height && w.y + w.h > r.y)
            .sort((a, b) => b.order - a.order)
    }
    // The captures are kept by window: the list of windows (and so the
    // captures) changes only when one comes, goes or changes places in the
    // stack; a window moving only moves its capture. Rebuilding them on every
    // refresh restarted each capture several times a second.
    property var windowIds: []
    property var frames: ({})
    onWindowsChanged: {
        const f = {}
        for (const w of windows) f[w.id] = w
        frames = f
        const ids = windows.map((w) => w.id)
        if (ids.join() !== windowIds.join()) windowIds = ids
    }
    // Hyprland's addresses, with or without their 0x, compared as one.
    function addressOf(a) { return a ? String(a).replace(/^0x/, "") : "" }
    // A capture lets go of a window the moment it closes: Hyprland's
    // closewindow drops it at once (before any refresh), and each capture
    // finds its window in Quickshell's own list, which drops it as it goes.
    // Captures kept until the next refresh went on copying a window that was
    // gone, which could bring Quickshell down.
    property var closing: ({})
    function windowClosed(address) {
        const id = addressOf(address)
        if (!id) return
        const c = Object.assign({}, closing); c[id] = true; closing = c
        if (frames[id]) { const f = Object.assign({}, frames); delete f[id]; frames = f }
        if (windowIds.includes(id)) windowIds = windowIds.filter((w) => w !== id)
        forget.restart()
    }
    Timer { id: forget; interval: 5000; onTriggered: bd.closing = ({}) }    // addresses aren't reused that soon
    function toplevelOf(id) {
        const t = Hyprland.toplevels.values.find((w) => bd.addressOf(w.address ?? w.lastIpcObject?.address) === id)
        return t?.wayland ?? null
    }
    Repeater {
        model: bd.windowIds
        delegate: ScreencopyView {
            required property string modelData
            readonly property var frame: bd.frames[modelData] ?? null
            visible: !!frame
            x: frame?.x ?? 0; y: frame?.y ?? 0
            width: frame?.w ?? 0; height: frame?.h ?? 0
            captureSource: bd.shown && frame && !bd.closing[modelData] ? bd.toplevelOf(modelData) : null
            // Frames on a clock (bd.capturing), not every one the window
            // draws: a window under the glass is copied at most 30 times a
            // second rather than at its own rate, and only while glass here
            // is bending it.
            live: false
            Connections {
                target: bd
                function onTick() { if (captureSource) captureFrame() }
            }
            onCaptureSourceChanged: if (captureSource) captureFrame()
        }
    }
    signal tick()
    Timer {
        id: capturing
        interval: 33; repeat: true
        running: bd.following && bd.windowIds.length > 0
        onTriggered: bd.tick()
    }

    // The texture every piece of glass in the surface samples: the part of
    // the backdrop the surface covers.
    ShaderEffectSource {
        id: texture
        parent: bd.parent
        visible: false
        sourceItem: Backdrops.used(texture) ? bd : null
        live: true
        sourceRect: Qt.rect(bd.at.x, bd.at.y, bd.surface.width, bd.surface.height)
        textureSize: Backdrops.textureSize(bd.surface.width, bd.surface.height, Screen.devicePixelRatio)
        Component.onDestruction: Backdrops.remove(texture)
    }

    // Where the surface is: the preview harness knows (__x, __y); Hyprland
    // lists every layer surface with its place.
    readonly property var previewAt: bd.surface.__x !== undefined ? Qt.point(bd.surface.__x, bd.surface.__y) : null
    onPreviewAtChanged: locate()
    onFixedAtChanged: locate()
    function locate() {
        if (previewAt) { at = previewAt; placed = true; return }
        if (fixedAt) { at = fixedAt; placed = true; return }
        if (namespace && !layers.running) layers.running = true
    }
    // Its glass bends it once it's known where the surface is and the
    // wallpaper is in (until then the compositor's blur is behind the glass).
    readonly property bool ready: placed && wallpaper.status === Image.Ready
    onReadyChanged: if (ready) Backdrops.add(bd.parent, bd, texture, bd)
    Process {
        id: layers
        command: ["hyprctl", "layers", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let data = null
                try { data = JSON.parse(text) } catch (e) { return }
                const mon = Hyprland.monitorFor(bd.screen)
                const levels = data?.[mon?.name]?.levels ?? {}
                for (const level of Object.values(levels)) {
                    for (const l of level) {
                        if (l.namespace !== bd.namespace || Math.abs(l.w - bd.surface.width) > 2 || Math.abs(l.h - bd.surface.height) > 2) continue
                        bd.at = Qt.point(l.x - (mon?.x ?? 0), l.y - (mon?.y ?? 0))
                        bd.placed = true
                        return
                    }
                }
            }
        }
    }
    Timer { id: relocate; interval: 60; onTriggered: bd.locate() }
    onShownChanged: if (shown) { Hyprland.refreshToplevels(); relocate.restart() }

    // Live: the windows' places are asked of Hyprland again whenever one
    // opens, closes, moves between workspaces or changes mode, and, because
    // dragging or resizing a window sends no event, several times a second
    // while some glass here is bending the backdrop. Without that a surface
    // that's always shown (the Dock) kept the windows it saw at login.
    readonly property bool following: includeWindows && Prefs.glassWindows && shown && Backdrops.used(texture)
    onFollowingChanged: if (following) Hyprland.refreshToplevels()
    Timer { interval: 100; repeat: true; running: bd.following; onTriggered: Hyprland.refreshToplevels() }
    Timer { id: refreshSoon; interval: 16; onTriggered: Hyprland.refreshToplevels() }
    Connections {
        target: Hyprland
        enabled: bd.following
        function onRawEvent(event) {
            if (["openwindow", "closewindow", "movewindowv2", "changefloatingmode", "fullscreen", "workspacev2", "activewindowv2"].includes(event.name))
                refreshSoon.restart()
        }
    }
    Connections {
        target: Hyprland
        enabled: bd.includeWindows
        function onRawEvent(event) {
            if (event.name === "closewindow") bd.windowClosed(event.parse(1)[0] ?? "")
        }
    }
    Connections {
        target: bd.surface
        ignoreUnknownSignals: true
        function onWidthChanged() { relocate.restart() }
        function onHeightChanged() { relocate.restart() }
    }
    Component.onCompleted: locate()
}
